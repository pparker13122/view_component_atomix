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
require_relative "styles/immutable"
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
require_relative "styles/declaration_queue"
require_relative "styles/owner_state"
require_relative "styles/accessors"
require_relative "styles/theme_compiler"
require_relative "styles/theme_resolution"
require_relative "styles/base"

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

        ThemeCompiler.compile(vars.id, vars.names, overrides)
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
          owners.each { |owner| owner.send(:styles_state).reset! }
          registry.clear
          dynamic_styles.clear
          @vars = nil
          config.reset! # Keep Rails configuration references valid.
        end
      end

      def owners
        includers.flat_map { |owner| owner.is_a?(Class) ? [owner, *owner.descendants] : [owner] }.uniq
      end

      def invalidate_caches!
        RESOLUTION_MONITOR.synchronize do
          owners.each do |owner|
            owner.send(:styles_state).invalidate!
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
            styles_state.variables << DeclarationQueue::VariableDeclaration.new(
              label: label, block: block, source: block.source_location.first
            )
          else
            definitions = inline if definitions.nil?
            Vars.validate_definitions!(definitions)
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
          styles_state.themes << DeclarationQueue::ThemeDeclaration.new(
            vars: vars, overrides: overrides, block: block, source: source
          )
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
