# frozen_string_literal: true

module ViewComponent
  module Atomix
    Rule = Struct.new(:selector, :property, :value, :conditions, :priority, keyword_init: true) do
      def initialize(selector:, property:, value:, conditions: [], priority: nil)
        super(
          selector: Immutable.copy(selector),
          property: Immutable.copy(property),
          value: Immutable.copy(value),
          conditions: Immutable.copy(conditions),
          priority: priority || Property.priority(property, conditions)
        )
        freeze
      end

      def to_css
        pseudos = conditions.reject { |c| c.start_with?("@") }
                            .sort_by { |c| c.start_with?("::") ? 1 : 0 }
        at_rules = conditions.select { |c| c.start_with?("@") }
                             .sort_by { |c| Property.condition_priority(c) }

        # StyleX adds one class per at-rule so a matching media query can
        # override a pseudo-class even when cascade layers are disabled.
        repetitions = 0
        if selector.start_with?(".")
          repetitions = at_rules.length
          repetitions += 1 if pseudos.any? { |pseudo| pseudo.include?(":where(") }
        end
        css = "#{selector * (1 + repetitions)}#{pseudos.join}{#{declarations}}"
        at_rules.reverse_each { |at| css = "#{at}{#{css}}" }
        css
      end

      private

      def declarations
        Array(value).map { |v| "#{property}:#{v}" }.join(";")
      end
    end
  end
end
