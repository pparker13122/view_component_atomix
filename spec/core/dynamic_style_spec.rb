# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::DynamicStyle do
  let!(:registry) { with_fresh_registry }

  it "forwards positional and keyword arguments through every sheet accessor" do
    sheet = ViewComponent::Atomix.create(box: {
      dynamic: %i[width height], using: ->(height, width:) { { width: width, height: height } }
    })

    [sheet.box(20, width: 10), sheet.fetch(:box, 20, width: 10), sheet[:box].call(20, width: 10)].each do |style|
      expect(style.inline.values).to contain_exactly("10px", "20px")
    end
  end

  it "supports optional keywords and empty keyword values" do
    sheet = ViewComponent::Atomix.create(box: {
      dynamic: [:width], using: ->(width: 10) { { width: width } }
    })
    expect(sheet.box.inline.values).to eq(["10px"])
    expect(sheet.box(width: nil).classes).to eq("width" => nil)
    expect(sheet.box(width: false).classes).to eq("width" => nil)
  end

  it "registers var-backed rules at definition time" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(w, h) { { width: w, height: h } })
    css = registry.rules.map(&:to_css)
    style = dynamic.call(1, 2)
    expect(css).to contain_exactly(
      ".#{style.classes["width"].first}{width:var(#{style.inline.key("1px")})}",
      ".#{style.classes["height"].first}{height:var(#{style.inline.key("2px")})}"
    )
  end

  it "returns a style with inline vars when called" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } })
    style = dynamic.call(120)
    expect(style.class_names).to match(/\Avc\w+\z/)
    expect(style.inline_style).to match(/\A--vc\w+:120px\z/)
    expect(registry.rules.map(&:to_css)).to eq([".#{style.class_names}{width:var(#{style.inline.keys.first})}"])
  end

  it "unsets nil results and returns an empty style for missing args" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } })
    expect(dynamic.call(nil).classes).to eq("width" => nil)
    expect(dynamic.call).to be_empty
  end

  it "calls a lambda with only optional arguments when invoked bare" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(width = 10) { { width: width } })

    expect(dynamic.call.inline_style).to include(":10px")
  end

  it "survives lambdas that do arithmetic on their arguments" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(n) { { width: n * 2, opacity: n / 10.0 } })
    expect(registry.size).to eq(2)
    expect(dynamic.call(5).inline_style).to include(":10px").and include(":0.5")
  end

  it "rejects a lambda whose body is not one literal hash" do
    expect do
      described_class.new(name: "spec", set: :size, fn: ->(n) { raise "boom" unless n; { width: n } })
    end.to raise_error(ViewComponent::Atomix::DynamicProperties::Unsupported, /must return one literal Hash/)
  end

  it "accepts explicitly declared properties for arbitrary lambdas" do
    dynamic = described_class.new(
      name: "spec", set: :size, properties: %i[width height],
      fn: ->(value) { value ? { width: value } : { height: 0 } }
    )

    expect(registry.size).to eq(2)
    expect(dynamic.call(3).classes.keys).to eq(["width"])
    expect(dynamic.call(false).inline.values).to eq(["0"])
  end

  it "rejects properties that were not compiled" do
    dynamic = described_class.new(name: "spec", set: :size, properties: [:width], fn: ->(_) { { height: 2 } })

    expect { dynamic.call(true) }.to raise_error(ArgumentError, /undeclared property "height"/)
  end

  it "is deterministic across instances with the same identity" do
    a = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } }).call(1)
    b = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } }).call(1)
    expect(a.class_names).to eq(b.class_names)
    expect(a.inline).to eq(b.inline)
  end
end

RSpec.describe "dynamic fallback arrays" do
  [true, false].each do |inline|
    it "rejects fallback arrays with inline=#{inline} and remains callable after failure" do
      registry = with_fresh_registry
      allow(ViewComponent::Atomix.config).to receive(:inline?).and_return(inline)
      sheet = ViewComponent::Atomix.create(box: ->(value) { { position: value } })
      baseline = registry.to_css
      expect { sheet.box(%w[sticky fixed]) }.to raise_error(ArgumentError, /Array.*position.*static trait/)
      expect(registry.to_css).to eq(baseline)
      expect(sheet.box("sticky").inline.values).to eq(["sticky"])
    end
  end
end
