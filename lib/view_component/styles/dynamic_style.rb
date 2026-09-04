# frozen_string_literal: true

module ViewComponent
  module Styles
    class DynamicStyle
      attr_reader :name, :set

      def initialize(name:, set:, fn:, properties: nil)
        @name = name
        @set = set
        @fn = fn
        @vars = {}
        @mutex = Mutex.new
        @declared_properties = normalize_properties(properties)
        @compiled_properties = @declared_properties
        compile! if Styles.config.inline?
        Styles.dynamic_styles << self
      end

      def arity
        @fn.arity
      end

      def call(*args)
        return Style::EMPTY if args.empty? && arity != 0
        return Style::EMPTY if !args.empty? && args.all? { |arg| arg.nil? || arg == false }

        result = @fn.call(*args)
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
          if value.nil?
            classes[property] = nil
            next
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
        @compiled_properties.each { |property| ensure_registered(property) }
        self
      end

      private

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
