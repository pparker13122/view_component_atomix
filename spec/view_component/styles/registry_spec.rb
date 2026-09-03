# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Registry do
  let!(:registry) { with_fresh_registry }

  it "dedupes identical rules" do
    ViewComponent::Styles.create(a: { color: "red" })
    ViewComponent::Styles.create(b: { color: "red" })
    expect(registry.size).to eq(1)
  end

  it "emits rules sorted by priority so longhands beat shorthands without layers" do
    ViewComponent::Styles.create(a: { padding_top: 1, padding: 2, color: { active: "a", hover: "h" } })
    css = registry.to_css
    expect(css).not_to include("@layer")
    expect(css.lines.length).to eq(4)
    expect(css.index("padding:2px")).to be < css.index("padding-top:1px")
    expect(css.index(":hover{color:h}")).to be < css.index(":active{color:a}")
  end

  it "can wrap rules in cascade layers" do
    allow(ViewComponent::Styles.config).to receive(:use_layers).and_return(true)
    ViewComponent::Styles.create(a: { padding_top: 1, padding: 2, color: { active: "a", hover: "h" } })
    css = registry.to_css
    expect(css).to start_with("@layer vc1000,vc4000,vc4130,vc4170;")
    expect(css.index("padding:2px")).to be < css.index("padding-top:1px")
  end

  it "invalidates the cached css when rules are added" do
    ViewComponent::Styles.create(a: { color: "red" })
    first = registry.to_css
    ViewComponent::Styles.create(a: { color: "blue" })
    expect(registry.to_css).not_to eq(first)
    registry.clear
    expect(registry.to_css).to eq("")
  end
end
