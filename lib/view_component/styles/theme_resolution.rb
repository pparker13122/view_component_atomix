# frozen_string_literal: true

module ViewComponent
  module Styles
    module ThemeResolution
      private

      def resolved_theme
        styles_resolution_monitor.synchronize do
          return styles_state.theme_resolved if styles_state.theme_resolved

          styles_state.themes.drain do |declaration|
            built = ViewComponent::Styles.registry.with_source(declaration.source) do
              build_theme(declaration.vars, declaration.overrides, declaration.block)
            end
            styles_state.theme_own = (styles_state.theme_own || Style::EMPTY).merge(built)
          end

          inherited = inherited_theme
          merged = styles_mixins.select { |mod| mod < Theme && theme_accessor_for(mod) == :theme }
          layers = [inherited, companion_theme, *merged.map { |mod| mod.send(:resolved_theme) },
                    styles_state.theme_own || Style::EMPTY]
          styles_state.theme_resolved = layers.reduce(Style::EMPTY, :merge)
        end
      end

      def inherited_theme
        return Style::EMPTY unless is_a?(Class) && superclass.respond_to?(:resolved_theme, true)

        superclass.send(:resolved_theme)
      end

      def build_theme(vars, overrides, block)
        overrides = block.call if block
        return ViewComponent::Styles.create_theme(vars, **overrides) if vars

        sheet = resolved_styles
        grouped = overrides.group_by do |key, _|
          owner = sheet.vars_for(key) ||
            raise(KeyError, "Unknown var #{key.inspect} in theme for #{self}. Available vars: #{sheet.var_names.inspect}")
          owner.id
        end
        ViewComponent::Styles.registry.transaction(independent: true) do
          grouped.map do |id, pairs|
            names = pairs.to_h { |key, _| [key.to_sym, sheet.vars_for(key).var_name(key)] }
            ThemeCompiler.compile(id, names, pairs.to_h)
          end.reduce(Style::EMPTY, :merge)
        end
      end
    end
  end
end
