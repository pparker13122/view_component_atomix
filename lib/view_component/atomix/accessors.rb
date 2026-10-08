# frozen_string_literal: true

module ViewComponent
  module Atomix
    module Accessors
      ACCESSOR_SUFFIX = /_(styles?|theme|vars|variables)\z/.freeze

      def styles_method(name = nil)
        return current_styles_method if name.nil?

        @_styles_method_explicit = true
        install_styles_method(name)
      end

      private

      def install_styles_method(name)
        name = name.to_sym
        previous = current_styles_method
        if previous && previous != name
          singleton_class.send(:undef_method, previous) if singleton_class.method_defined?(previous)
          undef_method(previous) if method_defined?(previous)
        end

        define_singleton_method(name) { |definitions = nil, &block| define_styles(definitions, &block) }
        define_method(name) { self.class.send(:resolved_styles) }
        @_styles_method = name
        invalidate_styles
        styles_mixins.each { |mod| define_mixin_accessors(mod) }
        name
      end

      def current_styles_method
        return @_styles_method if defined?(@_styles_method)

        is_a?(Class) && superclass.respond_to?(:styles_method) ? superclass.styles_method : nil
      end

      def styles_method_explicit?
        defined?(@_styles_method_explicit) && @_styles_method_explicit
      end

      def styles_mixins
        @_styles_mixins ||= []
      end

      def inherited_styles_mixin_accessors
        return {} unless is_a?(Class) && superclass.respond_to?(:styles_mixin_accessors, true)

        superclass.send(:styles_mixin_accessors)
      end

      # Separate readers select the last included module. Once a reader is
      # the primary accessor, its modules are represented by inherited_styles
      # instead, including any declarations which override them on that owner.
      def styles_mixin_accessors
        accessors = inherited_styles_mixin_accessors
        styles_mixins.each do |mod|
          accessors[styles_accessor_for(mod)] = mod if mod < Variables
        end
        accessors.delete(current_styles_method)
        accessors
      end

      def accessor_base(mod)
        mod.name.underscore.tr("/", "_").sub(ACCESSOR_SUFFIX, "")
      end

      def styles_accessor_for(mod)
        return mod.styles_method if mod.name.nil? || mod.send(:styles_method_explicit?)

        :"#{accessor_base(mod)}_styles"
      end

      def theme_accessor_for(mod)
        return :theme if mod.name.nil?

        :"#{accessor_base(mod)}_theme"
      end

      def companion_styles_module
        return styles_state.companion_styles_module if styles_state.companion_styles_module
        return unless is_a?(Class) && name

        candidate = "#{name}Styles".safe_constantize
        return unless candidate.instance_of?(Module) && candidate < Base

        styles_state.companion_styles_module = candidate
      end

      def companion_styles
        mod = companion_styles_module
        mod && mod < Variables ? mod.send(:resolved_styles) : Sheet::EMPTY
      end

      def companion_theme
        mod = companion_styles_module
        mod && mod < Theme ? mod.send(:resolved_theme) : Style::EMPTY
      end

      def add_styles_mixin(mod)
        styles_mixins << mod
        invalidate_styles
        define_mixin_accessors(mod)
      end

      def define_mixin_accessors(mod)
        if mod < Variables
          accessor = styles_accessor_for(mod)
          unless accessor == current_styles_method
            define_singleton_method(accessor) { mod.send(:resolved_styles) }
            define_method(accessor) { mod.send(:resolved_styles) }

            leaked = mod.styles_method
            undef_method(leaked) if leaked != accessor && leaked != current_styles_method && method_defined?(leaked)
          end
        end

        return unless mod < Theme

        accessor = theme_accessor_for(mod)
        return if accessor == :theme

        define_singleton_method(accessor) { mod.send(:resolved_theme) }
        define_method(accessor) { mod.send(:resolved_theme) }
      end
    end
  end
end
