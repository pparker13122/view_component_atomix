# frozen_string_literal: true

module ViewComponent
  module Styles
    class DynamicStyle
      class Placeholder < BasicObject
        def to_s = "0"
        def to_str = "0"
        def to_i = 0
        def to_f = 0.0
        def coerce(other) = [self, other]
        def respond_to?(*) = true
        def nil? = false
        def method_missing(*) = self
        def respond_to_missing?(*) = true
      end

      attr_reader :name, :set

      def initialize(name:, set:, fn:)
        @name = name
        @set = set
        @fn = fn
        @vars = {}
        @mutex = Mutex.new
        probe
        freeze
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
          if value.nil?
            classes[property] = nil
            next
          end

          var, class_name = ensure_registered(property)
          classes[property] = [class_name]
          inline[var] = Property.normalize_value(property, value)
        end
        Style.new(classes, inline)
      end

      private

      def probe
        placeholders = Array.new(arity.negative? ? arity.abs - 1 : arity) { Placeholder.new }
        result = @fn.call(*placeholders)
        result.each_key { |key| ensure_registered(Property.normalize_key(key)) } if result.is_a?(Hash)
      rescue StandardError, NoMethodError => e
        warn "[ViewComponent::Styles] Could not probe dynamic style #{name}.#{set}: #{e.message}. " \
             "Its CSS will only be registered when first called."
      end

      def ensure_registered(property)
        @mutex.synchronize do
          @vars[property] ||= begin
            var = Hashing.var_name(name, set, property)
            value = "var(#{var})"
            class_name = Hashing.class_name(property, value)
            Styles.registry.add(Rule.new(selector: ".#{class_name}", property: property, value: value))
            [var, class_name].freeze
          end
        end
      end
    end
  end
end
