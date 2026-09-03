# frozen_string_literal: true

module ViewComponent
  module Styles
    class Sheet
      attr_reader :sets, :vars

      def initialize(sets = {}, vars = {})
        @sets = sets.freeze
        @vars = vars.freeze
        freeze
      end

      EMPTY = new

      def [](name)
        return nil if name.nil?

        key = name.to_sym
        return sets[key] if sets.key?(key)

        owner = vars_for(key)
        return owner[key] if owner

        raise KeyError, "Unknown style set #{name.inspect}. Available sets: #{names.inspect}, vars: #{var_names.inspect}"
      end

      def fetch(name, *args)
        set = self[name]
        callable?(set) ? set.call(*args) : set
      end

      def key?(name)
        sets.key?(name.to_sym) || !vars_for(name).nil?
      end

      def names
        sets.keys
      end

      def var_names
        vars.keys
      end

      def vars_for(name)
        key = name.to_sym
        return vars[key] if vars.key?(key)

        global = ViewComponent::Styles.configured_vars
        global if global&.names&.key?(key)
      end

      def empty?
        sets.empty? && vars.empty?
      end

      def merge(other)
        return self if other.nil? || other.empty?

        Sheet.new(sets.merge(other.sets), vars.merge(other.vars))
      end

      def to_h
        sets
      end

      def props(*styles)
        ViewComponent::Styles.props(*styles)
      end

      def method_missing(name, *args, &block)
        if sets.key?(name)
          set = sets[name]
          if callable?(set)
            set.call(*args)
          elsif args.empty?
            set
          else
            raise ArgumentError, "Style set #{name.inspect} is static and takes no arguments"
          end
        elsif args.empty? && (owner = vars_for(name))
          owner[name]
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        sets.key?(name) || !vars_for(name).nil? || super
      end

      private

      def callable?(set)
        set.is_a?(DynamicStyle) || set.is_a?(EnumeratedStyle)
      end
    end
  end
end
