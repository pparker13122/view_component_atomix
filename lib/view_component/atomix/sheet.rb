# frozen_string_literal: true

module ViewComponent
  module Atomix
    class Sheet
      attr_reader :sets, :vars

      def initialize(sets = {}, vars = {})
        @sets = Immutable.copy(sets)
        @vars = Immutable.copy(vars)
        freeze
      end

      EMPTY = new

      def [](name)
        return nil if name.nil?

        key = name.to_sym
        return sets[key] if sets.key?(key)

        owner = vars_for(key)
        return owner[key] if owner

        raise KeyError, "Unknown trait #{name.inspect}. Available sets: #{names.inspect}, vars: #{var_names.inspect}"
      end

      def fetch(name, *args, **kwargs)
        invoke(name, self[name], *args, **kwargs)
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

        global = ViewComponent::Atomix.configured_vars
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
        ViewComponent::Atomix.props(*styles)
      end

      def method_missing(name, *args, **kwargs, &block)
        if sets.key?(name)
          invoke(name, sets[name], *args, **kwargs)
        elsif args.empty? && kwargs.empty? && (owner = vars_for(name))
          owner[name]
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        sets.key?(name) || !vars_for(name).nil? || super
      end

      private

      def invoke(name, set, *args, **kwargs)
        return set.call(*args, **kwargs) if callable?(set)
        return set if args.empty? && kwargs.empty?

        raise ArgumentError, "Trait #{name.inspect} is static and takes no arguments"
      end

      def callable?(set)
        set.is_a?(DynamicStyle) || set.is_a?(EnumeratedStyle)
      end
    end
  end
end
