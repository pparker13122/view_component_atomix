# frozen_string_literal: true

module ViewComponent
  module Atomix
    class EnumeratedStyle
      attr_reader :name, :members, :default

      def initialize(name:, members:, default: nil)
        @name = Immutable.copy(name)
        @members = Immutable.copy(members)
        @default = Immutable.copy(default)
        freeze
      end

      def call(value = nil)
        value = default if value.nil? || value == false
        return Style::EMPTY if value.nil?

        unless value.respond_to?(:to_sym)
          raise KeyError, "Unknown member #{value.inspect} for trait #{name.inspect}. Available: #{members.keys.inspect}"
        end

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
