# frozen_string_literal: true

module ViewComponent
  module Atomix
    # Resolution state is resettable. Installed accessor names and mixin
    # metadata belong to Accessors and survive resets. Unload is terminal for
    # this owner; Rails creates a new owner when it loads the constant again.
    class OwnerState
      attr_accessor :styles_own, :styles_resolved, :styles_breakpoints, :styles_resolving, :variables_resolving,
                    :theme_own, :theme_resolved, :theme_resolving, :companion_styles_module
      attr_reader :styles, :variables, :themes, :revision

      def initialize
        reset!
      end

      def reset!
        @revision = (@revision || 0) + 1
        @styles_own = @styles_resolved = @styles_breakpoints = nil
        @styles_resolving = @variables_resolving = @theme_resolving = false
        @theme_own = @theme_resolved = @companion_styles_module = nil
        @styles = DeclarationQueue.new
        @variables = DeclarationQueue.new
        @themes = DeclarationQueue.new
      end

      def unload!
        @unloaded = true
        invalidate!
      end

      def unloaded?
        @unloaded == true
      end

      def invalidate!
        @revision += 1
        @styles_resolved = @theme_resolved = nil
      end
    end
  end
end
