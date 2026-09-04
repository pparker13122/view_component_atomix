# frozen_string_literal: true

module ViewComponent
  module Styles
    class OwnerState
      attr_accessor :styles_own, :styles_resolved, :styles_breakpoints, :styles_resolving,
                    :theme_own, :theme_resolved, :companion_styles_module
      attr_reader :styles, :variables, :themes

      def initialize
        reset!
      end

      def reset!
        @styles_own = @styles_resolved = @styles_breakpoints = nil
        @styles_resolving = false
        @theme_own = @theme_resolved = @companion_styles_module = nil
        @styles = DeclarationQueue.new
        @variables = DeclarationQueue.new
        @themes = DeclarationQueue.new
      end

      def invalidate!
        @styles_resolved = @theme_resolved = nil
      end
    end
  end
end
