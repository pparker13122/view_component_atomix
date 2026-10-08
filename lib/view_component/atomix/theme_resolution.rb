# frozen_string_literal: true

module ViewComponent
  module Atomix
    module ThemeResolution
      private

      def resolved_theme
        resolve_owner(:theme) do |reentrant|
          reentrant ? theme_context : compile_theme
        end
      end

      def compile_theme
        styles_state.themes.drain do |declaration|
          built = ViewComponent::Atomix.registry.with_source(declaration.source) do
            build_theme(declaration.vars, declaration.overrides, declaration.block)
          end
          styles_state.theme_own = (styles_state.theme_own || Style::EMPTY).merge(built)
        end

        theme_context
      end

      def theme_context
        inherited = inherited_theme
        matching_mixins = styles_mixins.select { |mod| mod < Theme && theme_accessor_for(mod) == :theme }
        layers = [inherited, companion_theme, *matching_mixins.map { |mod| mod.send(:resolved_theme) },
                  styles_state.theme_own || Style::EMPTY]
        layers.reduce(Style::EMPTY, :merge)
      end

      def inherited_theme
        return Style::EMPTY unless is_a?(Class) && superclass.respond_to?(:resolved_theme, true)

        superclass.send(:resolved_theme)
      end

      def build_theme(vars, overrides, block)
        overrides = block.call if block
        unless overrides.is_a?(Hash)
          raise ArgumentError, "Theme overrides must be a Hash, got #{overrides.class}"
        end

        if vars
          return commit_owner_declaration do
            ViewComponent::Atomix.create_theme(vars, **overrides)
          end
        end

        sheet = resolved_styles
        grouped = overrides.group_by do |key, _|
          owner = sheet.vars_for(key) ||
            raise(KeyError, "Unknown var #{key.inspect} in theme for #{self}. Available vars: #{sheet.var_names.inspect}")
          owner.id
        end
        commit_owner_declaration do
          grouped.map do |id, pairs|
            names = pairs.to_h { |key, _| [key.to_sym, sheet.vars_for(key).var_name(key)] }
            ThemeCompiler.compile(id, names, pairs.to_h)
          end.reduce(Style::EMPTY, :merge)
        end
      end
    end
  end
end
