# frozen_string_literal: true

module ViewComponent
  module Styles
    Rule = Struct.new(:selector, :property, :value, :conditions, :priority, keyword_init: true) do
      def initialize(selector:, property:, value:, conditions: [], priority: nil)
        super(
          selector: selector,
          property: property,
          value: value,
          conditions: conditions.freeze,
          priority: priority || Property.priority(property, conditions)
        )
        freeze
      end

      def to_css
        pseudos = conditions.reject { |c| c.start_with?("@") }
                            .sort_by { |c| c.start_with?("::") ? 1 : 0 }
        at_rules = conditions.select { |c| c.start_with?("@") }
                             .sort_by { |c| Property.condition_priority(c) }

        css = "#{selector}#{pseudos.join}{#{declarations}}"
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
