# frozen_string_literal: true

module ViewComponent
  module Styles
    class Compiler
      def self.compile(definitions, name:, context: Sheet::EMPTY, breakpoints: {})
        Styles.registry.transaction { new(name, context, breakpoints).compile(definitions) }
      end

      def initialize(name, context = Sheet::EMPTY, breakpoints = {})
        @name = name
        @context = context
        @breakpoints = Styles.config.breakpoints.merge(breakpoints)
        @sets = {}
      end

      def compile(definitions)
        unless definitions.is_a?(Hash)
          raise ArgumentError, "Style definitions must be a Hash of style sets, got #{definitions.class}"
        end

        definitions.each do |set_name, definition|
          set_name = set_name.to_sym
          reject_property_name(set_name)
          @sets[set_name] = compile_set(set_name, definition)
        end
        Sheet.new(@sets)
      end

      private

      def reject_property_name(set_name)
        return unless Property.known?(Property.normalize_key(set_name))

        raise ArgumentError, "Style set #{set_name.inspect} is named after a CSS property. Pick another name."
      end

      def compile_set(set_name, definition)
        case definition
        when Proc
          DynamicStyle.new(name: @name, set: set_name, fn: definition)
        when Hash
          if dynamic_definition?(definition)
            compile_dynamic(set_name, definition)
          else
            classify(set_name, definition)
          end
        else
          raise ArgumentError, "Style set #{set_name.inspect} must be a Hash or a lambda, got #{definition.class}"
        end
      end

      def dynamic_definition?(definition)
        definition.key?(:dynamic) || definition.key?(:using)
      end

      def compile_dynamic(set_name, definition)
        unknown = definition.keys - %i[dynamic using]
        raise ArgumentError, "Dynamic style #{set_name.inspect} has unknown options #{unknown.inspect}" if unknown.any?

        properties = definition[:dynamic]
        fn = definition[:using]
        unless properties.is_a?(Array) && properties.all? { |property| property.is_a?(Symbol) || property.is_a?(String) }
          raise ArgumentError, "Dynamic style #{set_name.inspect} requires dynamic: with an Array of property names"
        end
        raise ArgumentError, "Dynamic style #{set_name.inspect} requires using: with a lambda" unless fn.is_a?(Proc)

        DynamicStyle.new(name: @name, set: set_name, fn: fn, properties: properties)
      end

      def classify(set_name, definition)
        references = {}
        members = {}
        properties = {}
        default = nil

        definition.each do |key, value|
          if key == :default
            if value.is_a?(Hash)
              raise ArgumentError,
                    "Default for style set #{set_name.inspect} must name a member, not define styles"
            end
            default = value
          elsif breakpoint_key?(key) && value.is_a?(Hash)
            raise ArgumentError,
                  "#{key.inspect} in style set #{set_name.inspect} is a configured breakpoint, so it cannot name a " \
                  "member. Conditions must be nested under a property, and members need a name that is not a breakpoint."
          elsif reference_key?(key)
            references[key] = value
          elsif member_key?(key, value)
            members[key] = value
          else
            properties[key] = value
          end
        end

        if members.any? && (references.any? || properties.any?)
          raise ArgumentError,
                "Style set #{set_name.inspect} mixes enumerated members #{members.keys.inspect} with " \
                "#{(references.keys + properties.keys).inspect}. A trait is either a list of members or a style."
        end
        if default && members.empty?
          raise ArgumentError, "Style set #{set_name.inspect} has a default but no members"
        end

        if members.any?
          compile_enumerated(set_name, members, default)
        elsif references.any?
          compile_combination(set_name, references, properties)
        else
          compile_style(definition)
        end
      end

      def reference_key?(key)
        key.is_a?(Symbol) && lookup(key)
      end

      def member_key?(key, value)
        return false unless key.is_a?(Symbol) && value.is_a?(Hash)
        return false if Property.known?(Property.normalize_key(key))
        return false if Styles.config.pseudo_map.key?(key) || breakpoint_key?(key)

        true
      end

      def lookup(key)
        @sets[key] || (@context.sets[key] if @context.sets.key?(key))
      end

      def compile_enumerated(set_name, members, default)
        members.each do |member, styles|
          condition = styles.keys.find { |key| condition_key?(key) && !pseudo_element_key?(key) }
          next unless condition

          raise ArgumentError,
                "Enumerated member #{member.inspect} in trait #{set_name.inspect} contains condition #{condition.inspect}. " \
                "Conditions must be nested under a property. If #{member.inspect} was intended as a property, check its spelling."
        end
        compiled = members.to_h { |member, styles| [member, compile_style(styles)] }
        if default
          default = default.to_sym
          unless compiled.key?(default)
            raise ArgumentError,
                  "Default #{default.inspect} is not a member of trait #{set_name.inspect}. " \
                  "Members: #{compiled.keys.inspect}"
          end
        end
        EnumeratedStyle.new(name: set_name, members: compiled, default: default)
      end

      def compile_combination(set_name, references, properties)
        styles = references.map { |key, value| resolve_reference(set_name, key, value) }
        styles << compile_style(properties) if properties.any?
        Styles.merge(*styles)
      end

      def resolve_reference(set_name, key, value)
        target = lookup(key)
        case target
        when EnumeratedStyle
          if value == true
            raise ArgumentError, "Trait #{key.inspect} in #{set_name.inspect} is enumerated; pass a member such as #{key}: #{target.member_names.first.inspect}" if target.default.nil?
            target.call
          else
            target.call(value)
          end
        when DynamicStyle
          raise ArgumentError, "Trait #{set_name.inspect} cannot reference the dynamic style #{key.inspect}"
        else
          unless value == true
            raise ArgumentError, "Trait #{key.inspect} in #{set_name.inspect} is not enumerated; use #{key}: true or :#{key}"
          end
          target
        end
      end

      def compile_style(definition)
        classes = {}

        definition.each do |key, value|
          if pseudo_element_key?(key)
            condition = resolve_condition(key)
            unless value.is_a?(Hash)
              raise ArgumentError, "Pseudo-element #{key.inspect} must map to a Hash of properties"
            end

            value.each do |prop_key, prop_value|
              property = Property.normalize_key(prop_key)
              classes["#{condition}#{property}"] = compile_property(property, prop_value, [condition])
            end
          elsif condition_key?(key)
            raise ArgumentError,
                  "Condition #{key.inspect} must be nested under a property, e.g. " \
                  "color: { default: \"red\", #{key.inspect} => \"blue\" }"
          else
            property = Property.normalize_key(key)
            classes[property] = compile_property(property, value, [])
          end
        end

        Style.new(classes)
      end

      def compile_property(property, value, conditions)
        case value
        when nil
          conditions.empty? ? nil : []
        when Hash
          value.flat_map do |key, nested|
            if key == :default
              Array(compile_property(property, nested, conditions))
            else
              compile_property(property, nested, conditions + [resolve_condition(key)])
            end
          end
        else
          normalized = Property.normalize_value(property, value)
          class_name = Hashing.class_name(property, normalized, conditions)
          Styles.registry.add(
            Rule.new(selector: ".#{class_name}", property: property, value: normalized, conditions: conditions)
          )
          [class_name]
        end
      end

      def pseudo_element_key?(key)
        resolved = key.is_a?(String) ? key : Styles.config.pseudo_map[key]
        resolved.is_a?(String) && resolved.start_with?("::")
      end

      def condition_key?(key)
        case key
        when String then key.start_with?(":", "@")
        when Symbol then Styles.config.pseudo_map.key?(key) || breakpoint_key?(key)
        else false
        end
      end

      def breakpoint_key?(key)
        key.is_a?(Symbol) && @breakpoints.key?(key)
      end

      def resolve_condition(key)
        Styles.config.resolve_condition(key, @breakpoints)
      end
    end
  end
end
