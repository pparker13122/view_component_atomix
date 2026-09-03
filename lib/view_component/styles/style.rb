# frozen_string_literal: true

module ViewComponent
  module Styles
    class Style
      attr_reader :classes, :inline

      def initialize(classes = {}, inline = {})
        @classes = classes.freeze
        @inline = inline.freeze
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
        attrs[:class] = class_names if class_names
        attrs[:style] = inline_style if inline_style
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
