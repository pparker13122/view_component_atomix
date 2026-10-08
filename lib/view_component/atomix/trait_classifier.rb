# frozen_string_literal: true

module ViewComponent
  module Atomix
    # Classifies the DSL without emitting CSS. Available references contain only
    # inherited sets and sets compiled earlier in declaration order.
    class TraitClassifier
      Result = Struct.new(:kind, :properties, :references, :members, :default, :fn, keyword_init: true)

      def initialize(sets:, inherited_sets:, conditions:)
        @sets = sets
        @inherited_sets = inherited_sets
        @conditions = conditions
      end

      def classify(set_name, definition)
        if Property.known?(Property.normalize_key(set_name))
          raise ArgumentError, "Trait #{set_name.inspect} is named after a CSS property. Pick another name."
        end
        if Sheet.method_defined?(set_name)
          raise ArgumentError, "Trait #{set_name.inspect} collides with a method on the styles sheet. Pick another name."
        end

        case definition
        when Proc
          Result.new(kind: :dynamic, fn: definition)
        when Hash
          if definition.key?(:dynamic) || definition.key?(:using)
            classify_dynamic(set_name, definition)
          else
            classify_hash(set_name, definition)
          end
        else
          raise ArgumentError, "Trait #{set_name.inspect} must be a Hash or a lambda, got #{definition.class}"
        end
      end

      private

      def classify_dynamic(set_name, definition)
        unknown = definition.keys - %i[dynamic using]
        raise ArgumentError, "Dynamic trait #{set_name.inspect} has unknown options #{unknown.inspect}" if unknown.any?

        properties = definition[:dynamic]
        fn = definition[:using]
        unless properties.is_a?(Array) && properties.all? { |property| property.is_a?(Symbol) || property.is_a?(String) }
          raise ArgumentError, "Dynamic trait #{set_name.inspect} requires dynamic: with an Array of property names"
        end
        raise ArgumentError, "Dynamic trait #{set_name.inspect} requires using: with a lambda" unless fn.is_a?(Proc)

        Result.new(kind: :dynamic, fn: fn, properties: properties)
      end

      def classify_hash(set_name, definition)
        references = {}
        members = {}
        properties = {}
        default = nil

        definition.each do |key, value|
          if key == :default
            if value.is_a?(Hash)
              raise ArgumentError,
                    "Default for trait #{set_name.inspect} must name a member, not define styles"
            end
            default = value
          elsif @conditions.breakpoint?(key) && value.is_a?(Hash)
            raise ArgumentError,
                  "#{key.inspect} in trait #{set_name.inspect} is a configured breakpoint, so it cannot name a " \
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
                "Trait #{set_name.inspect} mixes enumerated members #{members.keys.inspect} with " \
                "#{(references.keys + properties.keys).inspect}. A trait is either a list of members or a style."
        end
        if default && members.empty?
          raise ArgumentError, "Trait #{set_name.inspect} has a default but no members"
        end

        if members.any?
          Result.new(kind: :enumerated, members: members, default: default)
        elsif references.any?
          Result.new(kind: :combination, references: references, properties: properties)
        else
          Result.new(kind: :plain, properties: definition)
        end
      end

      def reference_key?(key)
        key.is_a?(Symbol) && (@sets.key?(key) || @inherited_sets.key?(key))
      end

      def member_key?(key, value)
        return false unless key.is_a?(Symbol) && value.is_a?(Hash)
        return false if Property.known?(Property.normalize_key(key))
        return false if @conditions.condition?(key)

        true
      end
    end
  end
end
