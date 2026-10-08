# frozen_string_literal: true

module ViewComponent
  module Atomix
    class Compiler
      def self.compile(definitions, name:, context: Sheet::EMPTY, breakpoints: {})
        Atomix.registry.transaction { new(name, context, breakpoints).compile(definitions) }
      end

      def initialize(name, context = Sheet::EMPTY, breakpoints = {})
        @name = name
        @context = context
        @conditions = Atomix.config.condition_resolver(Atomix.config.breakpoints.merge(breakpoints))
        @sets = {}
        @classifier = TraitClassifier.new(sets: @sets, inherited_sets: context.sets, conditions: @conditions)
      end

      def compile(definitions)
        unless definitions.is_a?(Hash)
          raise ArgumentError, "Style definitions must be a Hash of traits, got #{definitions.class}"
        end

        definitions.each do |set_name, definition|
          set_name = set_name.to_sym
          @sets[set_name] = compile_set(set_name, definition)
        end
        Sheet.new(@sets)
      end

      private

      def compile_set(set_name, definition)
        result = @classifier.classify(set_name, definition)
        case result.kind
        when :dynamic
          DynamicStyle.new(name: @name, set: set_name, fn: result.fn, properties: result.properties)
        when :enumerated
          compile_enumerated(set_name, result.members, result.default)
        when :combination
          compile_combination(set_name, result.references, result.properties)
        when :plain
          compile_style(result.properties)
        end
      end

      def lookup(key)
        @sets[key] || (@context.sets[key] if @context.sets.key?(key))
      end

      def compile_enumerated(set_name, members, default)
        members.each do |member, styles|
          condition = styles.keys.find { |key| @conditions.condition?(key) && !@conditions.pseudo_element?(key) }
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
        Atomix.merge(*styles)
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
          raise ArgumentError, "Trait #{set_name.inspect} cannot reference the dynamic trait #{key.inspect}"
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
          if @conditions.pseudo_element?(key)
            condition = @conditions.resolve(key)
            unless value.is_a?(Hash)
              raise ArgumentError, "Pseudo-element #{key.inspect} must map to a Hash of properties"
            end

            value.each do |prop_key, prop_value|
              property = Property.normalize_key(prop_key)
              classes["#{condition}#{property}"] = compile_property(property, prop_value, [condition])
            end
          elsif @conditions.condition?(key)
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
              compile_property(property, nested, conditions + [@conditions.resolve(key)])
            end
          end
        else
          normalized = Property.normalize_value(property, value)
          class_name = Hashing.class_name(property, normalized, conditions)
          Atomix.registry.add(
            Rule.new(selector: ".#{class_name}", property: property, value: normalized, conditions: conditions)
          )
          [class_name]
        end
      end
    end
  end
end
