# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::DynamicProperties do
  it "associates modifier lambdas with their actual opening lines" do
    fn = ->(a) { { width: a } } if (
      condition = -> { { height: 1 } }
    )
    later = ->(a) { { opacity: a } }

    expect(described_class.extract(fn, name: "Spec", set: :box)).to eq(["width"])
    expect(described_class.extract(condition, name: "Spec", set: :box)).to eq(["height"])
    expect(described_class.extract(later, name: "Spec", set: :box)).to eq(["opacity"])
  end

  %w[if unless while until].each do |modifier|
    it "indexes lambdas independently of #{modifier} modifier tree order" do
      parser = described_class::SourceParser.new("x = ->(a) { { width: a } } #{modifier} (\n-> { { height: 1 } }\n)\n")
      expect(parser.parse).not_to be_nil
      expect(described_class.properties_from(parser.lambdas.fetch(1).first, "Spec", :box)).to eq(["width"])
      expect(described_class.properties_from(parser.lambdas.fetch(2).first, "Spec", :box)).to eq(["height"])
    end
  end

  it "tracks nested lambdas, including default parameter values" do
    fn = ->(value = -> { { height: 1 } }) {
      { width: -> { { opacity: 1 } }.call.size }
    }
    # The outer lambda shares its opening line with its default, so ambiguity
    # must still be rejected rather than selecting either node arbitrarily.
    expect { described_class.extract(fn, name: "Spec", set: :box) }
      .to raise_error(described_class::Unsupported, /multiple lambdas/)
  end

  it "extracts empty multiline lambdas and nested value lambdas" do
    empty = -> {
      {}
    }
    outer = -> {
      { width: -> { 10 }.call }
    }
    expect(described_class.extract(empty, name: "Spec", set: :box)).to eq([])
    expect(described_class.extract(outer, name: "Spec", set: :box)).to eq(["width"])
  end

  it "extracts static keys without executing value expressions" do
    called = false
    fn = ->(x) { { width: x, opacity: (called = true) } }

    expect(described_class.extract(fn, name: "Spec", set: :box)).to eq(%w[width opacity])
    expect(called).to be(false)
  end

  it "locates a zero-argument lambda whose hash starts on the next line" do
    fn = -> {
      { color: "red" }
    }

    expect(described_class.extract(fn, name: "Spec", set: :box)).to eq(["color"])
  end

  it "rejects conditional hash shapes" do
    fn = ->(x) { x ? { width: x } : { height: x } }

    expect do
      described_class.extract(fn, name: "Spec", set: :box)
    end.to raise_error(described_class::Unsupported, /must return one literal Hash/)
  end

  it "rejects computed keys" do
    fn = ->(key, value) { { key => value } }

    expect do
      described_class.extract(fn, name: "Spec", set: :box)
    end.to raise_error(described_class::Unsupported, /property key must be a literal/)
  end
end

RSpec.describe "dynamic literal string keys" do
  it "decodes Ruby escapes consistently with runtime keys" do
    fn = ->(value) { { "\x77idth" => value, "\u0068eight" => value } }
    dynamic = ViewComponent::Styles::DynamicStyle.new(name: "escaped", set: :box, fn: fn)
    expect(dynamic.call(12).classes.keys).to eq(%w[width height])
  end

  it "preserves single-quoted escapes and rejects interpolated strings without evaluating them" do
    literal = ->(value) { { '\x77idth' => value } }
    expect(ViewComponent::Styles::DynamicProperties.extract(literal, name: "single", set: :box)).to eq(['\x77idth'])
    executed = false
    computed = ->(value) { { "border-#{executed = true}" => value } }
    expect { ViewComponent::Styles::DynamicProperties.extract(computed, name: "computed", set: :box) }
      .to raise_error(ViewComponent::Styles::DynamicProperties::Unsupported)
    expect(executed).to be(false)
  end
end

RSpec.describe "percent string property keys" do
  it "supports literal percent strings without evaluating interpolation" do
    fn = ->(value) { { %q(width) => value, %Q(he\x69ght) => value } }
    expect(ViewComponent::Styles::DynamicProperties.extract(fn, name: "percent", set: :box)).to eq(%w[width height])
  end
end
