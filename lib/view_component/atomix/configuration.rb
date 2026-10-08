# frozen_string_literal: true

module ViewComponent
  module Atomix
    class Configuration
      DEFAULT_PSEUDO_MAP = {
        hover: ":hover",
        focus: ":focus",
        focus_visible: ":focus-visible",
        focus_within: ":focus-within",
        active: ":active",
        visited: ":visited",
        link: ":link",
        target: ":target",
        disabled: ":disabled",
        enabled: ":enabled",
        checked: ":checked",
        indeterminate: ":indeterminate",
        required: ":required",
        optional: ":optional",
        valid: ":valid",
        invalid: ":invalid",
        read_only: ":read-only",
        placeholder_shown: ":placeholder-shown",
        empty: ":empty",
        first_child: ":first-child",
        last_child: ":last-child",
        only_child: ":only-child",
        first_of_type: ":first-of-type",
        last_of_type: ":last-of-type",
        before: "::before",
        after: "::after",
        placeholder: "::placeholder",
        selection: "::selection",
        marker: "::marker",
        dark: "@media (prefers-color-scheme: dark)",
        light: "@media (prefers-color-scheme: light)",
        reduced_motion: "@media (prefers-reduced-motion: reduce)",
        print: "@media print"
      }.freeze

      CLASS_PREFIX = /\A[a-zA-Z_][a-zA-Z0-9_-]*\z/

      attr_accessor :vars, :eager_load_paths, :autoload_roots, :use_layers, :inline, :output_path
      attr_reader :styles_method, :breakpoints, :class_prefix, :pseudo_map
      alias inline? inline

      def initialize
        reset!
      end

      def reset!
        @class_prefix = "vc"
        @breakpoints = {}
        @pseudo_map = DEFAULT_PSEUDO_MAP.dup
        @output_path = "app/assets/builds/view_component_atomix.css"
        @vars = nil
        @eager_load_paths = ["app/components", "app/components/styles", "app/styles"]
        @autoload_roots = ["app/components/styles"]
        @use_layers = false
        @inline = true
        @styles_method = :styles
      end

      def styles_method=(name)
        @styles_method = name.to_sym
      end

      def class_prefix=(prefix)
        prefix = prefix.to_s
        unless prefix.match?(CLASS_PREFIX)
          raise ArgumentError, "class_prefix must start with a letter or underscore and contain only " \
                               "letters, digits, hyphens and underscores, got #{prefix.inspect}"
        end

        @class_prefix = prefix
      end

      def pseudo_map=(map)
        raise ArgumentError, "pseudo_map must be a Hash, got #{map.class}" unless map.is_a?(Hash)

        map.each do |key, value|
          raise ArgumentError, "pseudo_map key must be a Symbol, got #{key.inspect}" unless key.is_a?(Symbol)
          unless value.is_a?(String) && value.start_with?(":", "@")
            raise ArgumentError, "pseudo_map #{key.inspect} must be a String starting with ':' or '@', got #{value.inspect}"
          end
        end
        ConditionResolver.validate_breakpoints!(breakpoints, pseudo_map: map)
        @pseudo_map = map.dup
      end

      def breakpoints=(map)
        validate_breakpoints!(map)
        @breakpoints = map.dup
      end

      def validate_breakpoints!(map)
        ConditionResolver.validate_breakpoints!(map, pseudo_map: pseudo_map)
      end

      def condition_resolver(breakpoints = self.breakpoints)
        ConditionResolver.new(breakpoints: breakpoints, pseudo_map: pseudo_map)
      end

      def resolve_condition(key, breakpoints = self.breakpoints)
        condition_resolver(breakpoints).resolve(key)
      end
    end
  end
end
