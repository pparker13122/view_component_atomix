# frozen_string_literal: true

module ViewComponent
  module Styles
    class DynamicStyle
      attr_reader :name, :set

      def initialize(name:, set:, fn:, properties: nil)
        @name = name
        @set = set
        @fn = fn
        @required_arguments = fn.parameters.any? { |kind, _| kind == :req || kind == :keyreq }
        @vars = {}
        @mutex = Mutex.new
        @declared_properties = normalize_properties(properties)
        @compiled_properties = @declared_properties
        compile! if Styles.config.inline?
        Styles.registry.after_commit { Styles.dynamic_styles << self }
      end

      def source_path
        @fn.source_location&.first
      end

      def arity
        @fn.arity
      end

      def call(*args, **kwargs)
        return Style::EMPTY if args.empty? && kwargs.empty? && required_arguments?
        result = @fn.call(*args, **kwargs)
        unless result.is_a?(Hash)
          raise ArgumentError, "Dynamic style #{set.inspect} must return a Hash, got #{result.class}"
        end

        classes = {}
        inline = {}
        result.each do |key, value|
          property = Property.normalize_key(key)
          if @compiled_properties && !@compiled_properties.include?(property)
            raise ArgumentError,
                  "Dynamic style #{name}.#{set} returned undeclared property #{property.inspect}. " \
                  "Compiled properties: #{@compiled_properties.inspect}"
          end
          if value.nil? || value == false
            classes[property] = nil
            next
          end

          if value.is_a?(Hash)
            raise ArgumentError,
                  "Dynamic style #{name}.#{set} cannot use conditions for #{property.inspect}. " \
                  "Declare conditions in a static trait referencing a CSS variable instead."
          end

          if value.is_a?(Array)
            raise ArgumentError,
                  "Dynamic style #{name}.#{set} cannot use an Array for #{property.inspect}. " \
                  "Declare fallback arrays in a static trait; dynamic values must be single CSS values."
          end

          var, class_name = identifiers(property)
          classes[property] = [class_name]
          inline[var] = Property.normalize_value(property, value)
        end
        Style.new(classes, inline)
      end

      def compile!
        @mutex.synchronize do
          @compiled_properties ||= DynamicProperties.extract(@fn, name: name, set: set)
        end
        Styles.registry.with_source(@fn.source_location&.first) do
          @compiled_properties.each { |property| ensure_registered(property) }
        end
        self
      end

      private

      def required_arguments?
        @required_arguments
      end

      def normalize_properties(properties)
        return unless properties

        properties.map { |property| Property.normalize_key(property) }.uniq.freeze
      end

      def identifiers(property)
        @mutex.synchronize { @vars[property] ||= build_identifiers(property) }
      end

      def ensure_registered(property)
        var, class_name = identifiers(property)
        Styles.registry.add(
          Rule.new(selector: ".#{class_name}", property: property, value: "var(#{var})")
        )
      end

      def build_identifiers(property)
        var = Hashing.var_name(name, set, property)
        value = "var(#{var})"
        [var, Hashing.class_name(property, value)].freeze
      end
    end
  end
end
