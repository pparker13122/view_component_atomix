# frozen_string_literal: true

module ViewComponent
  module Atomix
    # One effective condition vocabulary per compilation. Variables use the
    # global map; component traits include their locally declared breakpoints.
    class ConditionResolver
      attr_reader :breakpoints, :pseudo_map

      def initialize(breakpoints:, pseudo_map:)
        self.class.validate_pseudo_map!(pseudo_map)
        self.class.validate_breakpoints!(breakpoints, pseudo_map: pseudo_map)
        @breakpoints = Immutable.copy(breakpoints)
        @pseudo_map = Immutable.copy(pseudo_map)
      end

      def breakpoint?(key)
        key.is_a?(Symbol) && breakpoints.key?(key)
      end

      def condition?(key)
        case key
        when String then key.start_with?(":", "@")
        when Symbol then pseudo_map.key?(key) || breakpoint?(key)
        else false
        end
      end

      def pseudo_element?(key)
        resolved = key.is_a?(String) ? key : pseudo_map[key]
        resolved.is_a?(String) && resolved.start_with?("::")
      end

      def self.validate_pseudo_map!(map)
        raise ArgumentError, "pseudo_map must be a Hash, got #{map.class}" unless map.is_a?(Hash)

        map.each do |key, value|
          raise ArgumentError, "pseudo_map key must be a Symbol, got #{key.inspect}" unless key.is_a?(Symbol)
          unless value.is_a?(String) && value.start_with?(":", "@")
            raise ArgumentError, "pseudo_map #{key.inspect} must be a String starting with ':' or '@', got #{value.inspect}"
          end
        end
      end

      def self.validate_breakpoints!(map, pseudo_map:)
        raise ArgumentError, "breakpoints must be a Hash, got #{map.class}" unless map.is_a?(Hash)

        map.each do |key, query|
          raise ArgumentError, "breakpoint name must be a Symbol, got #{key.inspect}" unless key.is_a?(Symbol)
          raise ArgumentError, "breakpoint #{key.inspect} must be a String, got #{query.inspect}" unless query.is_a?(String)
          if pseudo_map.key?(key)
            raise ArgumentError, "breakpoint #{key.inspect} collides with the pseudo-class or media shortcut of the same name"
          end
        end
      end

      def resolve(key)
        case key
        when Symbol
          if (breakpoint = breakpoints[key])
            return breakpoint.start_with?("@") ? breakpoint : "@media #{breakpoint}"
          end

          pseudo_map[key] ||
            raise(ArgumentError, "Unknown style condition #{key.inspect}. " \
                                 "Use a known pseudo-class symbol, a configured breakpoint, " \
                                 "or a string such as \":nth-child(2)\" or \"@media (...)\".")
        when String
          unless key.start_with?(":", "@")
            raise ArgumentError, "Style condition strings must start with ':' or '@', got #{key.inspect}"
          end
          key
        else
          raise ArgumentError, "Unsupported style condition #{key.inspect}"
        end
      end
    end
  end
end
