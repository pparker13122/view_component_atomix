# frozen_string_literal: true

module ViewComponent
  module Atomix
    class Style
      attr_reader :classes, :inline

      def initialize(classes = {}, inline = {})
        assign(Immutable.copy(classes), Immutable.copy(inline))
      end

      def self.combine(styles)
        styles = styles.reject(&:empty?)
        return EMPTY if styles.empty?
        return styles.first if styles.one?

        classes = {}
        inline = {}
        styles.each do |style|
          classes.update(style.classes)
          inline.update(style.inline)
        end
        allocate.send(:assign, classes.freeze, inline.freeze)
      end

      def merge(other)
        return self if other.nil? || other.empty?

        Style.combine([self, other])
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

      private

      def assign(classes, inline)
        @classes = classes
        @inline = inline
        freeze
      end

      EMPTY = new
    end
  end
end
