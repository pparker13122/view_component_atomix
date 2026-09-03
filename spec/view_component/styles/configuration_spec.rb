# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Configuration do
  subject(:config) { described_class.new }

  it "defaults to inline delivery, the builds directory and no layers" do
    expect(config).to be_inline
    expect(config.output_path).to eq("app/assets/builds/view_component_styles.css")
    expect(config.use_layers).to be(false)
    expect(config.class_prefix).to eq("vc")
    expect(config.styles_method).to eq(:styles)
    expect(config.eager_load_paths).to eq(["app/components", "app/components/styles", "app/styles"])
  end

  it "stores the styles method name as a symbol" do
    config.styles_method = "css"
    expect(config.styles_method).to eq(:css)
  end

  it "prefixes bare breakpoint queries and rejects unknown conditions" do
    config.breakpoints = { sm: "(max-width: 600px)", md: "@media (max-width: 768px)" }
    expect(config.resolve_condition(:sm)).to eq("@media (max-width: 600px)")
    expect(config.resolve_condition(:md)).to eq("@media (max-width: 768px)")
    expect(config.resolve_condition(:hover)).to eq(":hover")
    expect(config.resolve_condition("@supports (display: grid)")).to eq("@supports (display: grid)")
    expect { config.resolve_condition(:bogus) }.to raise_error(ArgumentError, /Unknown style condition/)
    expect { config.resolve_condition("hover") }.to raise_error(ArgumentError, /must start with/)
  end
end
