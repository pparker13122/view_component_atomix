# frozen_string_literal: true

module ViewComponent
  module Atomix
    module Base
      extend ActiveSupport::Concern

      included do
        ViewComponent::Atomix.includers << self
        extend Mixin unless is_a?(Class)
      end

      class_methods do
        include Accessors
        include ThemeResolution

        private

        def styles_state
          @_styles_state ||= OwnerState.new
        end

        def reset_styles!
          styles_state.reset!
        end

        def invalidate_styles_cache!
          styles_state.invalidate!
        end

        def unload_styles!
          styles_state.unload!
        end

        def styles_unloaded?
          styles_state.unloaded?
        end

        def define_styles(definitions = nil, &block)
          return resolved_styles if definitions.nil? && block.nil?

          unless self < ViewComponent::Atomix
            raise ArgumentError, "#{self} includes ViewComponent::Atomix::Variables only. " \
                                 "Include ViewComponent::Atomix to declare traits."
          end

          source = block ? block.source_location.first : caller_locations(2, 1).first.path
          styles_resolution_monitor.synchronize do
            styles_state.styles << DeclarationQueue::StyleDeclaration.new(block: block || proc { definitions }, source: source)
            invalidate_styles
          end
          nil
        end

        def invalidate_styles
          ViewComponent::Atomix.invalidate_caches!
        end

        def resolved_styles
          resolve_owner(:styles) do |reentrant|
            reentrant ? compile_pending_vars : compile_pending_styles
            styles_context
          end
        end

        def resolve_owner(kind)
          cached = kind == :styles ? styles_state.styles_resolved : styles_state.theme_resolved
          return cached if cached

          styles_resolution_monitor.synchronize do
            ResolutionSession.with do |session|
              resolving = :"#{kind}_resolving"
              cache = :"#{kind}_resolved"
              if styles_state.public_send(resolving)
                session.provisional!
                return session.nested { yield true }
              end
              cached = styles_state.public_send(cache)
              return cached if cached

              outermost = !session.resolving?
              result = nil
              # An outer read gets one fresh cache-building pass after active
              # dependencies unwind. Successful declarations remain consumed.
              2.times do
                provisional = false
                session.frame do |frame|
                  # Immediate style_vars can drain deferred variables outside a
                  # styles read. Their in-progress owner is provisional too.
                  session.provisional! if kind == :styles && styles_state.variables_resolving
                  styles_state.public_send(:"#{resolving}=", true)
                  begin
                    result = resolve_stable(frame) { yield false }
                    provisional = frame.provisional
                    styles_state.public_send(:"#{cache}=", result) unless provisional
                  rescue StandardError
                    styles_state.public_send(:"#{cache}=", nil)
                    raise
                  ensure
                    styles_state.public_send(:"#{resolving}=", false)
                  end
                end
                break unless outermost && provisional

                outermost = false
              end
              result
            end
          end
        end

        def styles_resolution_monitor
          RESOLUTION_MONITOR
        end

        # Dependencies can declare more work on this owner while its context is
        # being assembled. Never overwrite their invalidation with a stale sheet.
        def resolve_stable(frame)
          ResolutionSession::MAX_STABILITY_PASSES.times do
            frame.stale = false
            result = yield
            return result unless frame.stale

            ResolutionSession.with(&:consume!)
          end
          raise ArgumentError, "Style dependencies keep changing during resolution"
        end

        def inherited_styles
          return Sheet::EMPTY unless is_a?(Class) && superclass.respond_to?(:resolved_styles, true)

          superclass.send(:resolved_styles)
        end

        def compile_pending_styles
          compile_pending_vars
          styles_state.styles.drain do |declaration|
            ViewComponent::Atomix.registry.with_source(declaration.source) do
              definitions, breakpoints = Builder.evaluate(self, declaration.block)
              sheet = commit_owner_declaration do
                previous_breakpoints = styles_state.styles_breakpoints
                begin
                  add_breakpoints(breakpoints)
                  Compiler.compile(definitions, name: name || "anonymous", context: styles_context,
                                   breakpoints: styles_breakpoints)
                rescue StandardError
                  styles_state.styles_breakpoints = previous_breakpoints
                  raise
                end
              end
              merge_own_styles(sheet)
            end
          end
        rescue StandardError
          styles_state.styles_resolved = nil
          raise
        end

        def compile_pending_vars
          previous = styles_state.variables_resolving
          styles_state.variables_resolving = true
          styles_state.variables.drain do |declaration|
            ViewComponent::Atomix.registry.with_source(declaration.source) do
              definitions = declaration.block.call
              add_vars(declaration.label, definitions)
            end
          end
        rescue StandardError
          styles_state.styles_resolved = nil
          raise
        ensure
          styles_state.variables_resolving = previous
        end

        def merge_own_styles(sheet)
          styles_state.styles_own = styles_state.styles_own ? styles_state.styles_own.merge(sheet) : sheet
        end

        def add_breakpoints(map)
          return if map.empty?

          # Inherited queries remain inherited so later parent declarations
          # cannot be shadowed by a snapshot taken on this owner.
          styles_state.styles_breakpoints = (styles_state.styles_breakpoints || {}).merge(map)
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
          matching_mixins = styles_mixins.select { |mod| mod < Variables && styles_accessor_for(mod) == current_styles_method }
          inherited_mixin = inherited_styles_mixin_accessors[current_styles_method]
          layers = [inherited_styles, inherited_mixin ? inherited_mixin.send(:resolved_styles) : Sheet::EMPTY,
                    companion_styles, *matching_mixins.map { |mod| mod.send(:resolved_styles) },
                    styles_state.styles_own || Sheet::EMPTY]
          layers.reduce(Sheet::EMPTY, :merge)
        end

        # Owner results survive a consuming transaction's failure, so their CSS
        # must commit independently. Keep user block evaluation outside this
        # boundary; publish the compiled result on the owner only
        # after it succeeds. Source attribution remains around both phases.
        def commit_owner_declaration(&block)
          ViewComponent::Atomix.registry.transaction(independent: true, &block)
        end

        def add_vars(label, definitions)
          vars = commit_owner_declaration { Vars.new(label, definitions) }
          merge_own_styles(Sheet.new({}, vars.names.keys.to_h { |key| [key, vars] }))
        end

        def macro_label(name)
          return name.to_s if name

          self.name || "anonymous:#{caller_locations(2, 1).first&.then { |l| "#{l.path}:#{l.lineno}" }}"
        end
      end
    end
  end
end
