# frozen_string_literal: true

module ViewComponent
  module Styles
    class Style
      attr_reader :classes, :inline

      def initialize(classes = {}, inline = {})
        @classes = Immutable.copy(classes)
        @inline = Immutable.copy(inline)
        freeze
      end

      EMPTY = new

      def merge(other)
        return self if other.nil? || other.empty?

        Style.new(classes.merge(other.classes), inline.merge(other.inline))
      end

      def empty?
        classes.empty? && inline.empty?
      end

      def class_names
        names = classes.values.compact.flatten
        names.empty? ? nil : names.join(" ")
      end

      def inline_style
        return nil if inline.empty?

        inline.map { |name, value| "#{name}:#{value}" }.join(";")
      end

      def to_attrs
        attrs = Attrs.new
        names = class_names
        declarations = inline_style
        attrs[:class] = names if names
        attrs[:style] = declarations if declarations
        attrs
      end

      def to_s
        class_names.to_s
      end

      def ==(other)
        other.is_a?(Style) && classes == other.classes && inline == other.inline
      end
      alias eql? ==

      def hash
        [classes, inline].hash
      end
    end
  end
end
