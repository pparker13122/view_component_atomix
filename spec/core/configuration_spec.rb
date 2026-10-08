# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::Configuration do
  subject(:config) { described_class.new }

  it "defaults to inline delivery, the builds directory and no layers" do
    expect(config).to be_inline
    expect(config.output_path).to eq("app/assets/builds/view_component_atomix.css")
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
  it "rejects invalid global breakpoints without replacing the previous configuration" do
    original = { small: "(max-width: 600px)" }
    config.breakpoints = original
    [nil, { hover: "(min-width: 1px)" }, { small: 600 }, { "small" => "(max-width: 600px)" }].each do |invalid|
      expect { config.breakpoints = invalid }.to raise_error(ArgumentError)
      expect(config.breakpoints).to eq(original)
    end
  end

  it "validates breakpoint entries changed through the mutable configuration map" do
    config.breakpoints[:hover] = "(min-width: 1px)"
    expect { config.resolve_condition(:hover) }.to raise_error(ArgumentError, /collides/)
  end

end
