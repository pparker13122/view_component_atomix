# frozen_string_literal: true

RSpec.describe "style directories" do
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
    expect(Rails.application.config.eager_load_paths).to include(dir)
  end

  it "eager loads both directories into the registry" do
    css = ViewComponent::Styles.eager_load!.to_css
    expect(css).to include(".#{CardStyles::CARD.root.classes["padding"].join}{padding:24px}")
    expect(css).to include(".#{BadgeStyles::BADGE.root.classes["font-size"].join}{font-size:12px}")
  end
end
