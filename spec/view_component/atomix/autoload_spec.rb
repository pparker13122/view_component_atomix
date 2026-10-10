# frozen_string_literal: true

require "rails_helper"

require "open3"

RSpec.describe "style directories" do
  it "removes reloadable rules while preserving shared and permanent rules" do
    registry = with_fresh_registry
    permanent = ViewComponent::Atomix.create(root: { color: "red" }).root
    source = Rails.root.join("app/styles/reload_brand.rb").to_s

    %w[red blue red].each do |color|
      registry.with_source(source) do
        ViewComponent::Atomix.define_vars(name: "ReloadBrand", accent: { default: color, dark: "black" })
        ViewComponent::Atomix.create(root: { color: "red", padding: 3 })
      end
      expect(registry.to_css).to include(":#{color}}")
      expect(registry.to_css.scan(/:root\{/).size).to eq(2)
      ActiveSupport::Reloader.new.run_callbacks(:class_unload)
      expect(registry.to_css).to eq(".#{permanent.class_names}{color:red}")
    end
  end

  it "tracks the source of lazy blocks, hash declarations, variables and themes" do
    registry = with_fresh_registry
    source = Rails.root.join("app/components/reload_example.rb").to_s
    klass = Class.new(ViewComponent::Base)
    klass.class_eval(<<~RUBY, source, 1)
      include ViewComponent::Atomix
      ViewComponent::Atomix.create(root: { background: "white" })
      style_vars gap: 2
      style_vars { { accent: "red" } }
      styles root: { padding: 9 }
      styles { trait :other, margin: 7 }
      styles { trait :box, dynamic: [:width], using: ->(width:) { { width: width } } }
      theme accent: "blue"
    RUBY
    klass.styles
    klass.theme
    expect(registry.size).to eq(7)
    ActiveSupport::Reloader.new.run_callbacks(:class_unload)
    expect(registry.to_css).to eq("")
  end

  it "keeps CSS registered by non-reloadable code across class unload" do
    registry = ViewComponent::Atomix::Registry.new
    allow(ViewComponent::Atomix).to receive(:registry).and_return(registry)
    allow(ViewComponent::Atomix).to receive(:includers).and_return([])
    allow(ViewComponent::Atomix).to receive(:dynamic_styles).and_return([])

    old_style = ViewComponent::Atomix.create(root: { color: "red" }).root
    old_class = old_style.class_names
    expect(registry.to_css).to include(".#{old_class}{color:red}")

    ActiveSupport::Reloader.new.run_callbacks(:class_unload)

    expect(registry.to_css).to include(".#{old_class}{color:red}")
  end

  it "autoloads app/components/styles at the top level" do
    expect(BadgeStyles::BADGE.root).to be_a(ViewComponent::Atomix::Style)
    expect(Object.const_defined?(:Styles)).to be(false)
  end

  it "registers app/components/styles as an autoload root" do
    dir = Rails.root.join("app/components/styles").to_s
    expect(Rails.autoloaders.main.dirs).to include(dir)
    expect(Rails.application.config.paths.eager_load).to include(dir)
  end

  it "compiles styles when Rails is loaded but no application is defined yet" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require "rails"
      require "view_component"
      require "view_component_atomix"
      sheet = ViewComponent::Atomix.create(root: { color: "red" })
      abort "expected a compiled rule" unless ViewComponent::Atomix.registry.to_css.include?(".#{sheet.root.class_names}{color:red}")
    SCRIPT
    output, status = Open3.capture2e("bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end

  it "leaves app/components/styles alone when autoload_roots is emptied before boot" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require "rails"
      require "view_component"
      require "view_component_atomix"
      ViewComponent::Atomix.config.autoload_roots = []
      require File.expand_path("spec/dummy/config/environment")
      dir = Rails.root.join("app/components/styles").to_s
      abort "expected #{dir} not to be an autoload root" if Rails.autoloaders.main.dirs.include?(dir)
      begin
        Rails.autoloaders.main.eager_load
        abort "expected eager loading to look for Styles::BadgeStyles in #{dir}"
      rescue Zeitwerk::NameError => e
        abort e.message unless e.message.include?("Styles::BadgeStyles")
      end
    SCRIPT
    output, status = Open3.capture2e({ "RAILS_ENV" => "production" }, "bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end

  it "eager loads both directories into the registry when the application boots" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require File.expand_path("spec/dummy/config/environment")
      css = ViewComponent::Atomix.registry.to_css
      expected = {
        "app/styles" => ".#{CardStyles::CARD.root.classes["padding"].join}{padding:24px}",
        "app/components/styles" => ".#{BadgeStyles::BADGE.root.classes["font-size"].join}{font-size:12px}"
      }
      missing = expected.reject { |_, rule| css.include?(rule) }.keys
      abort "registry is missing rules from #{missing.join(" and ")} after boot:\n#{css}" unless missing.empty?
    SCRIPT
    output, status = Open3.capture2e({ "RAILS_ENV" => "development" }, "bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end
end
