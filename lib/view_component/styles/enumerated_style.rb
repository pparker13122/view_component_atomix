# frozen_string_literal: true

module ViewComponent
  module Styles
    class EnumeratedStyle
      attr_reader :name, :members, :default

      def initialize(name:, members:, default: nil)
        @name = name
        @members = members.freeze
        @default = default
        freeze
      end

      def call(value = nil)
        value = default if value.nil?
        return Style::EMPTY if value.nil?

        key = value.to_sym
        return members[key] if members.key?(key)

        raise KeyError, "Unknown member #{value.inspect} for trait #{name.inspect}. Available: #{members.keys.inspect}"
      end
      alias [] call

      def member_names
        members.keys
      end

      def empty?
        members.empty?
      end
    end
  end
end
