# frozen_string_literal: true

module ViewComponent
  module Styles
    module Base
      extend ActiveSupport::Concern

      included do
        ViewComponent::Styles.includers << self
        extend Mixin unless is_a?(Class)
      end

      class_methods do
        include Accessors
        include ThemeResolution

        private

        def styles_state
          @_styles_state ||= OwnerState.new
        end

        def define_styles(definitions = nil, &block)
          return resolved_styles if definitions.nil? && block.nil?

          unless self < ViewComponent::Styles
            raise ArgumentError, "#{self} includes ViewComponent::Styles::Variables only. " \
                                 "Include ViewComponent::Styles to declare style sets."
          end

          source = block ? block.source_location.first : caller_locations(2, 1).first.path
          styles_state.styles << DeclarationQueue::StyleDeclaration.new(block: block || proc { definitions }, source: source)
          invalidate_styles
          nil
        end

        def invalidate_styles
          ViewComponent::Styles.invalidate_caches!
        end

        def resolved_styles
          styles_resolution_monitor.synchronize do
            if styles_state.styles_resolving
              compile_pending_vars
              return styles_context
            end
            return styles_state.styles_resolved if styles_state.styles_resolved

            begin
              styles_state.styles_resolving = true
              compile_pending_styles
              styles_state.styles_resolved = styles_context
            ensure
              styles_state.styles_resolving = false
            end
          end
        end

        def styles_resolution_monitor
          RESOLUTION_MONITOR
        end

        def inherited_styles
          return Sheet::EMPTY unless is_a?(Class) && superclass.respond_to?(:resolved_styles, true)

          superclass.send(:resolved_styles)
        end

        def compile_pending_styles
          compile_pending_vars
          styles_state.styles.drain do |declaration|
            ViewComponent::Styles.registry.with_source(declaration.source) do
              definitions, breakpoints = Builder.evaluate(self, declaration.block)
              ViewComponent::Styles.registry.transaction(independent: true) do
                previous_breakpoints = styles_state.styles_breakpoints
                begin
                  add_breakpoints(breakpoints)
                  add_styles(definitions)
                rescue StandardError
                  styles_state.styles_breakpoints = previous_breakpoints
                  raise
                end
              end
            end
          end
        rescue StandardError
          styles_state.styles_resolved = nil
          raise
        end

        def compile_pending_vars
          styles_state.variables.drain do |declaration|
            ViewComponent::Styles.registry.with_source(declaration.source) do
              definitions = declaration.block.call
              add_vars(declaration.label, definitions)
            end
          end
        rescue StandardError
          styles_state.styles_resolved = nil
          raise
        end

        def add_styles(definitions)
          sheet = Compiler.compile(definitions, name: name || "anonymous", context: styles_context,
                                                breakpoints: styles_breakpoints)
          styles_state.styles_own = styles_state.styles_own ? styles_state.styles_own.merge(sheet) : sheet
        end

        def add_breakpoints(map)
          return if map.empty?

          styles_state.styles_breakpoints = styles_breakpoints.merge(map)
        end

        def styles_breakpoints
          inherited = if is_a?(Class) && superclass.respond_to?(:styles_breakpoints, true)
                        superclass.send(:styles_breakpoints)
                      else
                        {}
                      end
          inherited.merge(styles_state.styles_breakpoints || {})
        end

        def styles_context
          merged = styles_mixins.select { |mod| mod < Variables && styles_accessor_for(mod) == current_styles_method }
          inherited_mixin = inherited_styles_mixin_accessors[current_styles_method]
          layers = [inherited_styles, inherited_mixin ? inherited_mixin.send(:resolved_styles) : Sheet::EMPTY,
                    companion_styles, *merged.map { |mod| mod.send(:resolved_styles) },
                    styles_state.styles_own || Sheet::EMPTY]
          layers.reduce(&:merge)
        end

        def add_vars(label, definitions)
          # Both immediate and deferred declarations publish owner state that
          # survives a consuming transaction's failure. Commit their CSS first.
          vars = ViewComponent::Styles.registry.transaction(independent: true) { Vars.new(label, definitions) }
          sheet = Sheet.new({}, vars.names.keys.to_h { |key| [key, vars] })
          styles_state.styles_own = styles_state.styles_own ? styles_state.styles_own.merge(sheet) : sheet
        end

        def macro_label(name)
          return name.to_s if name

          self.name || "anonymous:#{caller_locations(2, 1).first&.then { |l| "#{l.path}:#{l.lineno}" }}"
        end
      end
    end
  end
end
