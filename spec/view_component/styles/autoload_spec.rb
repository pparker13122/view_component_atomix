# frozen_string_literal: true

RSpec.describe "style directories" do
  it "removes reloadable rules while preserving shared and permanent rules" do
    registry = with_fresh_registry
    permanent = ViewComponent::Styles.create(root: { color: "red" }).root
    source = Rails.root.join("app/styles/reload_brand.rb").to_s

    %w[red blue red].each do |color|
      registry.with_source(source) do
        ViewComponent::Styles.define_vars(name: "ReloadBrand", accent: { default: color, dark: "black" })
        ViewComponent::Styles.create(root: { color: "red", padding: 3 })
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
      include ViewComponent::Styles
      ViewComponent::Styles.create(root: { background: "white" })
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
    registry = ViewComponent::Styles::Registry.new
    allow(ViewComponent::Styles).to receive(:registry).and_return(registry)
    allow(ViewComponent::Styles).to receive(:includers).and_return([])
    allow(ViewComponent::Styles).to receive(:dynamic_styles).and_return([])

    old_style = ViewComponent::Styles.create(root: { color: "red" }).root
    old_class = old_style.class_names
    expect(registry.to_css).to include(".#{old_class}{color:red}")

    ActiveSupport::Reloader.new.run_callbacks(:class_unload)

    expect(registry.to_css).to include(".#{old_class}{color:red}")
  end

  it "autoloads app/styles at the top level" do
    expect(CardStyles::CARD.root).to be_a(ViewComponent::Styles::Style)
  end

  it "autoloads app/components/styles at the top level" do
    expect(BadgeStyles::BADGE.root).to be_a(ViewComponent::Styles::Style)
    expect(Object.const_defined?(:Styles)).to be(false)
  end

  it "registers app/components/styles as an autoload root" do
    dir = Rails.root.join("app/components/styles").to_s
    expect(Rails.autoloaders.main.dirs).to include(dir)
    expect(Rails.application.config.paths.eager_load).to include(dir)
  end

  it "eager loads both directories into the registry" do
    css = ViewComponent::Styles.eager_load!.to_css
    expect(css).to include(".#{CardStyles::CARD.root.classes["padding"].join}{padding:24px}")
    expect(css).to include(".#{BadgeStyles::BADGE.root.classes["font-size"].join}{font-size:12px}")
  end
end
