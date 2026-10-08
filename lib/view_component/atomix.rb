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

require_relative "atomix/version"
require_relative "atomix/configuration"
require_relative "atomix/hashing"
require_relative "atomix/property"
require_relative "atomix/known_properties"
require_relative "atomix/immutable"
require_relative "atomix/condition_resolver"
require_relative "atomix/rule"
require_relative "atomix/registry"
require_relative "atomix/weak_collection"
require_relative "atomix/attrs"
require_relative "atomix/style"
require_relative "atomix/dynamic_properties"
require_relative "atomix/dynamic_style"
require_relative "atomix/enumerated_style"
require_relative "atomix/builder"
require_relative "atomix/sheet"
require_relative "atomix/vars"
require_relative "atomix/trait_classifier"
require_relative "atomix/compiler"
require_relative "atomix/attribute_helpers"
require_relative "atomix/helper"
require_relative "atomix/resolution_session"
require_relative "atomix/declaration_queue"
require_relative "atomix/owner_state"
require_relative "atomix/accessors"
require_relative "atomix/theme_compiler"
require_relative "atomix/theme_resolution"
require_relative "atomix/base"

module ViewComponent
  module Atomix
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
        raise ArgumentError, "ViewComponent::Atomix.create requires a Hash or a block" if definitions.nil?

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
                "No vars configured. Set `config.view_component.atomix.vars = -> { Brand::VARS }` " \
                "in an initializer, or assign `ViewComponent::Atomix.vars = ViewComponent::Atomix.define_vars(...)`.")
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
            next if k.send(:styles_unloaded?)
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
        Tempfile.create([".view_component_atomix", ".css"], path.dirname) do |file|
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
          owners.each { |owner| owner.send(:reset_styles!) }
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
            owner.send(:invalidate_styles_cache!)
          end
        end
      end

      def unload!(owner, source)
        if owner.is_a?(Module) && owner.respond_to?(:unload_styles!, true)
          owner.send(:unload_styles!)
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
          raise ArgumentError, "Dynamic trait #{style.set.inspect} must be called with arguments before use"
        else
          raise ArgumentError, "Expected a ViewComponent::Atomix::Style, got #{style.class}"
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
        [ViewComponent::Atomix, Variables, Theme].each do |concern|
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
        install_styles_method(ViewComponent::Atomix.config.styles_method)
      end

      class_methods do
        def style_vars(definitions = nil, name: nil, **inline, &block)
          label = macro_label(name)
          source = caller_locations(1, 1).first.path
          styles_resolution_monitor.synchronize do
            if block
              styles_state.variables << DeclarationQueue::VariableDeclaration.new(
                label: label, block: block, source: block.source_location.first
              )
            else
              definitions = inline if definitions.nil?
              Vars.validate_definitions!(definitions)
              raise ArgumentError, "style_vars requires a Hash or a block" if definitions.empty?

              compile_pending_vars
              ViewComponent::Atomix.registry.with_source(source) { add_vars(label, definitions) }
            end
            invalidate_styles
          end
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
          styles_resolution_monitor.synchronize do
            styles_state.themes << DeclarationQueue::ThemeDeclaration.new(
              vars: vars, overrides: overrides, block: block, source: source
            )
            invalidate_styles
          end
          nil
        end
      end

      def theme
        self.class.send(:resolved_theme)
      end
    end

    include Variables
    include Theme

    include AttributeHelpers
  end
end

require_relative "atomix/railtie" if defined?(Rails::Railtie)
