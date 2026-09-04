# frozen_string_literal: true

require "set"
require "fileutils"
require "pathname"
require "digest/sha1"
require "monitor"
require "tempfile"
require "active_support"
require "active_support/concern"
require "active_support/core_ext/string/output_safety"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/class/subclasses"
require "view_component"

require_relative "styles/version"
require_relative "styles/configuration"
require_relative "styles/hashing"
require_relative "styles/property"
require_relative "styles/known_properties"
require_relative "styles/rule"
require_relative "styles/registry"
require_relative "styles/weak_collection"
require_relative "styles/attrs"
require_relative "styles/style"
require_relative "styles/dynamic_properties"
require_relative "styles/dynamic_style"
require_relative "styles/enumerated_style"
require_relative "styles/builder"
require_relative "styles/sheet"
require_relative "styles/vars"
require_relative "styles/compiler"
require_relative "styles/helper"

module ViewComponent
  module Styles
    extend ActiveSupport::Concern

    class Error < StandardError; end
    class VarsNotConfigured < Error; end

    RESOLUTION_MONITOR = Monitor.new

    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config
      end

      def registry
        @registry ||= Registry.new
      end

      def includers
        @includers ||= WeakCollection.new
      end

      def dynamic_styles
        @dynamic_styles ||= WeakCollection.new
      end

      def compile_dynamic_styles!
        dynamic_styles.each(&:compile!)
      end

      def create(definitions = nil, name: nil, **inline_definitions, &block)
        breakpoints = {}
        if block && definitions.nil? && inline_definitions.empty?
          definitions, breakpoints = Builder.evaluate(nil, block)
        end
        definitions ||= inline_definitions.empty? ? nil : inline_definitions
        raise ArgumentError, "ViewComponent::Styles.create requires a Hash or a block" if definitions.nil?

        Compiler.compile(definitions, name: name || caller_name, breakpoints: breakpoints)
      end

      def define_vars(name: nil, **vars)
        Vars.new(name || caller_name, vars)
      end

      def create_theme(vars, **overrides)
        raise ArgumentError, "create_theme expects a Vars object" unless vars.is_a?(Vars)

        digest_input = overrides.sort_by { |k, _| k.to_s }.map { |k, v| "#{k}=#{v.inspect}" }
        class_name = Hashing.class_name("theme", vars.id, digest_input)
        registry.transaction do
          overrides.each do |key, value|
            Vars.register(".#{class_name}", vars.var_name(key), value)
          end
        end
        Style.new({ "theme:#{vars.id}" => [class_name] })
      end

      def vars
        configured_vars ||
          raise(VarsNotConfigured,
                "No vars configured. Set `config.view_component.styles.vars = -> { Brand::VARS }` " \
                "in an initializer, or assign `ViewComponent::Styles.vars = ViewComponent::Styles.define_vars(...)`.")
      end

      def vars=(vars)
        @vars = vars
      end

      def configured_vars
        resolved = @vars || config.vars
        resolved = resolved.call if resolved.respond_to?(:call)
        resolved = Object.const_get(resolved) if resolved.is_a?(String)
        resolved.is_a?(Vars) ? resolved : nil
      end

      def merge(*styles)
        styles.flatten.compact.reduce(Style::EMPTY) do |acc, style|
          acc.merge(coerce_style(style))
        end
      end

      def props(*styles)
        merge(*styles).to_attrs
      end

      def sx(*styles)
        props(*styles).to_s
      end

      def eager_load!
        if defined?(Rails) && Rails.respond_to?(:autoloaders) && Rails.application
          config.eager_load_paths.each do |relative|
            dir = Rails.root.join(relative)
            next unless dir.directory?

            Rails.autoloaders.main.eager_load_dir(dir.to_s)
          end
        end

        includers.each do |klass|
          targets = klass.is_a?(Class) ? [klass, *klass.descendants] : [klass]
          targets.each do |k|
            next if k.instance_variable_get(:@_styles_unloaded)
            k.send(:resolved_styles)
            k.send(:resolved_theme) if k < Theme
          end
        end
        registry
      end

      def write_css(path = nil, force: false)
        root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root : Pathname.new(Dir.pwd)
        path = root.join(path || config.output_path)
        css = "#{registry.to_css}\n"
        return path if !force && path.file? && File.binread(path) == css.b

        FileUtils.mkdir_p(path.dirname)
        Tempfile.create([".view_component_styles", ".css"], path.dirname) do |file|
          file.chmod(path.exist? ? path.stat.mode & 0o777 : 0o666 & ~File.umask)
          file.write(css)
          file.flush
          File.rename(file.path, path)
        end
        path
      end

      # A full reset discards declarations on existing owners as well as rules.
      # Standalone Style/Sheet/Vars objects must be recreated by the caller.
      def reset!
        RESOLUTION_MONITOR.synchronize do
          owners.each do |owner|
            owner.instance_variables.grep(/\A@_(styles_(own|resolved|blocks|breakpoints)|vars_blocks|theme_(own|resolved|pending)|companion_styles_module)\z/).each do |ivar|
              owner.remove_instance_variable(ivar)
            end
          end
          registry.clear
          dynamic_styles.clear
          @vars = nil
          config.send(:initialize) # Keep Rails configuration references valid.
        end
      end

      def owners
        includers.flat_map { |owner| owner.is_a?(Class) ? [owner, *owner.descendants] : [owner] }.uniq
      end

      def invalidate_caches!
        RESOLUTION_MONITOR.synchronize do
          owners.each do |owner|
            owner.instance_variable_set(:@_styles_resolved, nil)
            owner.instance_variable_set(:@_theme_resolved, nil)
          end
        end
      end

      def unload!(owner, source)
        if owner.is_a?(Module)
          owner.instance_variable_set(:@_styles_unloaded, true)
          includers.delete_if { |candidate| candidate.equal?(owner) }
        end
        dynamic_styles.delete_if { |style| style.source_path == source }
      end

      private

      def coerce_style(style)
        case style
        when Style then style
        when false then Style::EMPTY
        when EnumeratedStyle then style.call
        when DynamicStyle
          raise ArgumentError, "Dynamic style #{style.set.inspect} must be called with arguments before use"
        else
          raise ArgumentError, "Expected a ViewComponent::Styles::Style, got #{style.class}"
        end
      end

      def caller_name
        location = caller_locations(2, 1)&.first
        return "anonymous" unless location

        path = location.path
        root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : Dir.pwd
        path = path.delete_prefix("#{root}/")
        "#{path}:#{location.lineno}"
      end
    end

    module Mixin
      def append_features(base)
        [ViewComponent::Styles, Variables, Theme].each do |concern|
          base.include(concern) if self < concern && !(base < concern)
        end
        super
        base.send(:add_styles_mixin, self)
      end
    end

    module Base
      extend ActiveSupport::Concern

      ACCESSOR_SUFFIX = /_(styles?|theme|vars|variables)\z/.freeze

      included do
        ViewComponent::Styles.includers << self
        extend Mixin unless is_a?(Class)
      end

      class_methods do
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
          @_styles_resolved = nil
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
          return @_companion_styles_module if @_companion_styles_module
          return unless is_a?(Class) && name

          candidate = "#{name}Styles".safe_constantize
          return unless candidate.instance_of?(Module) && candidate < Base

          @_companion_styles_module = candidate
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
          @_styles_resolved = nil
          @_theme_resolved = nil
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

        def define_styles(definitions = nil, &block)
          return resolved_styles if definitions.nil? && block.nil?

          unless self < ViewComponent::Styles
            raise ArgumentError, "#{self} includes ViewComponent::Styles::Variables only. " \
                                 "Include ViewComponent::Styles to declare style sets."
          end

          source = block ? block.source_location.first : caller_locations(2, 1).first.path
          (@_styles_blocks ||= []) << [block || proc { definitions }, source]
          invalidate_styles
          nil
        end

        def invalidate_styles
          ViewComponent::Styles.invalidate_caches!
        end

        def resolved_styles
          styles_resolution_monitor.synchronize do
            if @_styles_resolving
              compile_pending_vars
              return styles_context
            end
            return @_styles_resolved if @_styles_resolved

            begin
              @_styles_resolving = true
              compile_pending_styles
              @_styles_resolved = styles_context
            ensure
              @_styles_resolving = false
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
          blocks = @_styles_blocks || []
          @_styles_blocks = []
          blocks.each_with_index do |(block, source), index|
            begin
              ViewComponent::Styles.registry.with_source(source) do
                definitions, breakpoints = Builder.evaluate(self, block)
                ViewComponent::Styles.registry.transaction(independent: true) do
                  previous_breakpoints = @_styles_breakpoints
                  begin
                    add_breakpoints(breakpoints)
                    add_styles(definitions)
                  rescue StandardError
                    @_styles_breakpoints = previous_breakpoints
                    raise
                  end
                end
              end
            rescue StandardError
              @_styles_blocks = blocks.drop(index) + @_styles_blocks
              @_styles_resolved = nil
              raise
            end
          end
        end

        def compile_pending_vars
          var_blocks = @_vars_blocks || []
          @_vars_blocks = []
          var_blocks.each_with_index do |(label, block), index|
            begin
              ViewComponent::Styles.registry.with_source(block.source_location.first) do
                definitions = block.call
                ViewComponent::Styles.registry.transaction(independent: true) { add_vars(label, definitions) }
              end
            rescue StandardError
              @_vars_blocks = var_blocks.drop(index) + @_vars_blocks
              @_styles_resolved = nil
              raise
            end
          end
        end

        def add_styles(definitions)
          sheet = Compiler.compile(definitions, name: name || "anonymous", context: styles_context,
                                                breakpoints: styles_breakpoints)
          @_styles_own = @_styles_own ? @_styles_own.merge(sheet) : sheet
        end

        def add_breakpoints(map)
          return if map.empty?

          @_styles_breakpoints = styles_breakpoints.merge(map)
        end

        def styles_breakpoints
          inherited = if is_a?(Class) && superclass.respond_to?(:styles_breakpoints, true)
                        superclass.send(:styles_breakpoints)
                      else
                        {}
                      end
          inherited.merge(@_styles_breakpoints || {})
        end

        def styles_context
          merged = styles_mixins.select { |mod| mod < Variables && styles_accessor_for(mod) == current_styles_method }
          layers = [inherited_styles, companion_styles, *merged.map { |mod| mod.send(:resolved_styles) },
                    @_styles_own || Sheet::EMPTY]
          layers.reduce(&:merge)
        end

        def add_vars(label, definitions)
          vars = Vars.new(label, definitions)
          sheet = Sheet.new({}, vars.names.keys.to_h { |key| [key, vars] })
          @_styles_own = @_styles_own ? @_styles_own.merge(sheet) : sheet
        end

        def resolved_theme
          styles_resolution_monitor.synchronize do
            return @_theme_resolved if @_theme_resolved

            pending = @_theme_pending || []
            @_theme_pending = []
            pending.each_with_index do |(vars, overrides, block, source), index|
              begin
                built = ViewComponent::Styles.registry.with_source(source) { build_theme(vars, overrides, block) }
                @_theme_own = (@_theme_own || Style::EMPTY).merge(built)
              rescue StandardError
                @_theme_pending = pending.drop(index) + @_theme_pending
                raise
              end
            end

            inherited = is_a?(Class) && superclass.respond_to?(:resolved_theme, true) ? superclass.send(:resolved_theme) : Style::EMPTY
            merged = styles_mixins.select { |mod| mod < Theme && theme_accessor_for(mod) == :theme }
            @_theme_resolved = [inherited, companion_theme, *merged.map { |mod| mod.send(:resolved_theme) }]
                               .reduce(Style::EMPTY, :merge).merge(@_theme_own || Style::EMPTY)
          end
        end

        def build_theme(vars, overrides, block)
          overrides = block.call if block
          return ViewComponent::Styles.create_theme(vars, **overrides) if vars

          grouped = overrides.group_by do |key, _|
            resolved_styles.vars_for(key) ||
              raise(KeyError, "Unknown var #{key.inspect} in theme for #{self}. Available vars: #{resolved_styles.var_names.inspect}")
          end
          ViewComponent::Styles.registry.transaction(independent: true) do
            grouped.map { |owner, pairs| ViewComponent::Styles.create_theme(owner, **pairs.to_h) }.reduce(Style::EMPTY, :merge)
          end
        end

        def macro_label(name)
          return name.to_s if name

          self.name || "anonymous:#{caller_locations(2, 1).first&.then { |l| "#{l.path}:#{l.lineno}" }}"
        end
      end
    end

    module Variables
      extend ActiveSupport::Concern
      include Base

      included do
        install_styles_method(ViewComponent::Styles.config.styles_method)
      end

      class_methods do
        def style_vars(definitions = nil, name: nil, **inline, &block)
          label = macro_label(name)
          if block
            (@_vars_blocks ||= []) << [label, block]
          else
            definitions ||= inline
            raise ArgumentError, "style_vars requires a Hash or a block" if definitions.empty?

            compile_pending_vars
            ViewComponent::Styles.registry.with_source(caller_locations(1, 1).first.path) { add_vars(label, definitions) }
          end
          invalidate_styles
          nil
        end
      end
    end

    module Theme
      extend ActiveSupport::Concern
      include Base

      class_methods do
        def theme(vars = nil, **overrides, &block)
          return resolved_theme if vars.nil? && overrides.empty? && block.nil?

          raise ArgumentError, "theme expects a Vars object as its first argument" if vars && !vars.is_a?(Vars)

          source = block ? block.source_location.first : caller_locations(1, 1).first.path
          (@_theme_pending ||= []) << [vars, overrides, block, source]
          invalidate_styles
          nil
        end
      end

      def theme
        self.class.send(:resolved_theme)
      end
    end

    include Variables
    include Theme

    def sx(*styles)
      ViewComponent::Styles.sx(*styles)
    end

    def sx_attrs(*styles)
      ViewComponent::Styles.props(*styles)
    end
  end
end

require_relative "styles/railtie" if defined?(Rails::Railtie)
