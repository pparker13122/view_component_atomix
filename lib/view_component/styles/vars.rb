# frozen_string_literal: true

module ViewComponent
  module Styles
    class Vars
      attr_reader :id, :names

      def initialize(id, definitions)
        @id = id
        @names = {}
        @refs = {}

        Styles.registry.transaction do
          definitions.each do |key, value|
            var = Hashing.var_name(id, key)
            @names[key.to_sym] = var
            @refs[key.to_sym] = "var(#{var})"
            Vars.register(":root", var, value)
          end
        end

        @names.freeze
        @refs.freeze
        freeze
      end

      def [](key)
        @refs.fetch(key.to_sym) do
          raise KeyError, "Unknown var #{key.inspect}. Available vars: #{@refs.keys.inspect}"
        end
      end

      def var_name(key)
        @names.fetch(key.to_sym)
      end

      def to_h
        @refs
      end

      def method_missing(name, *args)
        return super unless @refs.key?(name) && args.empty?

        @refs[name]
      end

      def respond_to_missing?(name, include_private = false)
        @refs.key?(name) || super
      end

      def theme(**overrides)
        Styles.create_theme(self, **overrides)
      end

      def self.register(selector, var, value, conditions = [])
        case value
        when Hash
          value.each do |key, nested|
            next if nested.nil?

            if key == :default
              register(selector, var, nested, conditions)
            else
              register(selector, var, nested, conditions + [Styles.config.resolve_condition(key)])
            end
          end
        else
          Styles.registry.add(
            Rule.new(
              selector: selector,
              property: var,
              value: Property.normalize_value(var, value),
              conditions: conditions,
              priority: conditions.sum(0) { |c| Property.condition_priority(c) }
            )
          )
        end
      end
    end
  end
end
