# frozen_string_literal: true

RSpec.describe "style directories" do
  it "removes obsolete CSS before reloaded definitions register replacement rules" do
    registry = ViewComponent::Styles::Registry.new
    allow(ViewComponent::Styles).to receive(:registry).and_return(registry)
    allow(ViewComponent::Styles).to receive(:includers).and_return([])
    allow(ViewComponent::Styles).to receive(:dynamic_styles).and_return([])

    old_style = ViewComponent::Styles.create(root: { color: "red" }).root
    old_class = old_style.class_names
    expect(registry.to_css).to include(".#{old_class}{color:red}")

    ActiveSupport::Reloader.new.run_callbacks(:class_unload)

    new_style = ViewComponent::Styles.create(root: { color: "blue" }).root
    css = registry.to_css
    expect(css).to include(".#{new_style.class_names}{color:blue}")
    expect(css).not_to include(".#{old_class}{color:red}")
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
