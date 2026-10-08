# frozen_string_literal: true

module ViewComponent
  module Atomix
    class Builder
      attr_reader :definitions, :declared_breakpoints

      def initialize(owner)
        @owner = owner
        @definitions = {}
        @declared_breakpoints = {}
      end

      def breakpoints(**map)
        Atomix.config.validate_breakpoints!(map)
        @declared_breakpoints.merge!(map)
        nil
      end

      def trait(name, *args, **definition)
        raise ArgumentError, "trait name must be a Symbol, got #{name.inspect}" unless name.is_a?(Symbol)
        raise ArgumentError, "trait #{name.inspect} is already declared in this block" if @definitions.key?(name)

        @definitions[name] = build_definition(name, args, definition)
        nil
      end

      def self.evaluate(owner, block)
        builder = new(owner)
        returned = builder.instance_exec(&block)
        definitions = builder.definitions
        if definitions.empty?
          unless returned.nil? || returned.is_a?(Hash)
            raise ArgumentError, "styles block must declare traits or return a Hash, got #{returned.class}"
          end

          definitions = returned || {}
        elsif returned.is_a?(Hash)
          raise ArgumentError, "styles block must either declare traits or return a Hash, not both"
        end

        [definitions, builder.declared_breakpoints]
      end

      private

      def build_definition(name, args, definition)
        merged = {}
        args.each do |arg|
          case arg
          when Symbol then merged[arg] = true
          when Hash then merged.merge!(arg)
          when Proc
            raise ArgumentError, "trait #{name.inspect} cannot combine a lambda with other definitions" unless args.one? && definition.empty?

            return arg
          else
            raise ArgumentError, "trait #{name.inspect} accepts trait symbols, a Hash, or a lambda, got #{arg.inspect}"
          end
        end
        merged.merge!(definition)
      end

      def method_missing(name, *args, **kwargs, &block)
        if @owner&.respond_to?(name)
          @owner.public_send(name, *args, **kwargs, &block)
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        @owner&.respond_to?(name) || super
      end
    end
  end
end
