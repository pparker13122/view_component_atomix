# frozen_string_literal: true

module ViewComponent
  module Styles
    class Registry
      def initialize
        @mutex = Mutex.new
        @rules = {}
        @css = nil
      end

      def add(rule)
        @mutex.synchronize do
          unless @rules.key?(rule)
            @rules[rule] = @rules.size
            @css = nil
          end
        end
        rule
      end

      def clear
        @mutex.synchronize do
          @rules.clear
          @css = nil
        end
      end

      def rules
        @mutex.synchronize { @rules.keys }
      end

      def size
        @mutex.synchronize { @rules.size }
      end

      def to_css
        @mutex.synchronize do
          @css ||= build_css(@rules.keys)
        end
      end

      private

      def build_css(rules)
        sorted = rules.sort_by.with_index { |rule, i| [rule.priority, i] }

        unless Styles.config.use_layers
          return sorted.map(&:to_css).join("\n")
        end

        groups = sorted.group_by(&:priority)
        return "" if groups.empty?

        header = "@layer #{groups.keys.map { |p| layer_name(p) }.join(',')};"
        body = groups.map do |priority, group|
          "@layer #{layer_name(priority)}{\n#{group.map(&:to_css).join("\n")}\n}"
        end
        [header, *body].join("\n")
      end

      def layer_name(priority)
        "#{Styles.config.class_prefix}#{priority}"
      end
    end
  end
end
