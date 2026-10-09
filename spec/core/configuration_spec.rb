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
    expect(config.autoload_roots).to eq(["app/components/styles"])
  end

  it "rejects class prefixes that cannot start a class name" do
    ["", "9x", "-x", "a b", "a.b"].each do |prefix|
      expect { config.class_prefix = prefix }.to raise_error(ArgumentError, /class_prefix/)
    end
    expect(config.class_prefix).to eq("vc")
    config.class_prefix = :app_ui
    expect(config.class_prefix).to eq("app_ui")
  end

  it "validates and copies an assigned pseudo map" do
    config.breakpoints = { small: "(max-width: 600px)" }
    original = config.pseudo_map
    [nil, { "hover" => ":hover" }, { hover: "hover" }, { hover: nil }, { small: ":hover" }].each do |invalid|
      expect { config.pseudo_map = invalid }.to raise_error(ArgumentError)
      expect(config.pseudo_map).to equal(original)
    end

    assigned = { hover: ":hover" }
    config.pseudo_map = assigned
    assigned[:small] = ":first-child"
    expect(config.pseudo_map).to eq(hover: ":hover")
  end

  it "copies assigned breakpoints" do
    assigned = { small: "(max-width: 600px)" }
    config.breakpoints = assigned
    assigned[:hover] = "(min-width: 1px)"
    expect(config.breakpoints).to eq(small: "(max-width: 600px)")
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

  it "validates pseudo map entries changed through the mutable configuration map" do
    config.pseudo_map[:open] = "[open]"
    expect { config.resolve_condition(:hover) }.to raise_error(ArgumentError, /pseudo_map :open/)
  end
end
