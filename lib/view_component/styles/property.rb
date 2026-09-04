# frozen_string_literal: true

module ViewComponent
  module Styles
    module Property
      SHORTHANDS_OF_SHORTHANDS = %w[
        animation background border font grid grid-area
        inset margin mask padding scroll-margin scroll-padding
      ].to_set.freeze

      TIME_PROPERTIES = %w[
        animation-delay animation-duration transition-delay transition-duration voice-duration
      ].to_set.freeze

      ADDITIONAL_UNITLESS = %w[
        -webkit-line-clamp counter-set counter-reset hyphenate-limit-chars
        mask-border-outset mask-border-slice mask-border-width rotate
        shape-image-threshold math-depth
      ].to_set.freeze

      # These shorthands sit between their parent shorthand and other shorthands.
      INTERMEDIATE_SHORTHANDS = %w[border-block border-inline grid-template].to_set.freeze

      SHORTHANDS_OF_LONGHANDS = %w[
        animation-range background-position border-block-color border-block-end border-block-start
        border-block-style border-block-width border-bottom border-color
        border-image border-inline-color border-inline-end border-inline-start border-inline-style
        border-inline-width border-left border-radius border-right border-style border-top border-width
        caret column-rule columns
        contain-intrinsic-size container corner-shape flex flex-flow font-synthesis font-variant gap grid-column
        grid-gap grid-row inset-block inset-inline list-style margin-block
        margin-inline mask-border offset outline overflow overscroll-behavior padding-block
        padding-inline place-content place-items place-self position-try scroll-margin-block scroll-margin-inline
        scroll-padding-block scroll-padding-inline scroll-timeline text-box text-decoration
        text-emphasis text-wrap transition view-timeline white-space
      ].to_set.freeze

      UNITLESS = %w[
        animation-iteration-count aspect-ratio border-image-outset border-image-slice
        border-image-width box-flex box-flex-group box-ordinal-group column-count columns fill-opacity
        flex flex-grow flex-negative flex-order flex-positive flex-shrink flood-opacity font-weight
        grid-area grid-column grid-column-end grid-column-span grid-column-start grid-row
        grid-row-end grid-row-span grid-row-start line-clamp line-height opacity order orphans
        scale stop-opacity stroke-dasharray stroke-dashoffset stroke-miterlimit stroke-opacity
        stroke-width tab-size widows z-index zoom
      ].to_set.freeze

      AT_RULE_PRIORITIES = {
        "@supports" => 30,
        "@media" => 200,
        "@container" => 300
      }.freeze

      PSEUDO_CLASS_PRIORITIES = {
        ":is" => 40, ":where" => 40, ":not" => 40, ":has" => 45, ":dir" => 50, ":lang" => 51,
        ":first-child" => 52, ":first-of-type" => 53, ":last-child" => 54, ":last-of-type" => 55,
        ":only-child" => 56, ":only-of-type" => 57, ":nth-child" => 60, ":nth-last-child" => 61,
        ":nth-of-type" => 62, ":nth-last-of-type" => 63, ":empty" => 70, ":link" => 80,
        ":any-link" => 81, ":local-link" => 82, ":target-within" => 83, ":target" => 84,
        ":visited" => 85, ":enabled" => 91, ":disabled" => 92, ":required" => 93, ":optional" => 94,
        ":read-only" => 95, ":read-write" => 96, ":placeholder-shown" => 97, ":in-range" => 98,
        ":out-of-range" => 99, ":default" => 100, ":checked" => 101, ":indeterminate" => 101,
        ":blank" => 102, ":valid" => 103, ":invalid" => 104, ":user-invalid" => 105,
        ":autofill" => 110, ":picture-in-picture" => 120, ":modal" => 121, ":fullscreen" => 122,
        ":paused" => 123, ":playing" => 124, ":current" => 125, ":past" => 126, ":future" => 127,
        ":hover" => 130, ":focus-within" => 140, ":focus" => 150, ":focus-visible" => 160,
        ":active" => 170
      }.freeze

      DEFAULT_PSEUDO_CLASS_PRIORITY = 40
      PSEUDO_ELEMENT_PRIORITY = 5000
      LOGICAL_PATTERN = /(^|-)(block|inline|start|end)(-|$)/

      module_function

      def normalize_key(key)
        name = key.to_s
        return name if name.start_with?("--")

        name.gsub(/([a-z\d])([A-Z])/, '\1-\2').tr("_", "-").downcase
      end

      def normalize_value(property, value)
        case value
        when Array then value.map { |v| normalize_value(property, v) }
        when Integer, Float
          return value.to_s if property.start_with?("--") || ADDITIONAL_UNITLESS.include?(property)
          return "#{value}ms" if TIME_PROPERTIES.include?(property)
          return "0" if value.zero?
          UNITLESS.include?(property) ? value.to_s : "#{value}px"
        when Symbol then value.to_s.tr("_", "-")
        else value.to_s
        end
      end

      def base_priority(property)
        return 500 if property == "all"
        return 1000 if SHORTHANDS_OF_SHORTHANDS.include?(property)
        return 1500 if INTERMEDIATE_SHORTHANDS.include?(property)
        return 2000 if SHORTHANDS_OF_LONGHANDS.include?(property)
        return 3000 if property.match?(LOGICAL_PATTERN)

        4000
      end

      def condition_priority(condition)
        if condition.start_with?("@")
          AT_RULE_PRIORITIES.fetch(condition.split(/[\s(]/, 2).first, AT_RULE_PRIORITIES["@media"])
        elsif condition.start_with?("::")
          PSEUDO_ELEMENT_PRIORITY
        else
          PSEUDO_CLASS_PRIORITIES.fetch(condition.split("(", 2).first, DEFAULT_PSEUDO_CLASS_PRIORITY)
        end
      end

      def priority(property, conditions = [])
        conditions.sum(base_priority(property)) { |c| condition_priority(c) }
      end
    end
  end
end
