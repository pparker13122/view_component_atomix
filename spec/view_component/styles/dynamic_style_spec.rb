# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::DynamicStyle do
  let!(:registry) { with_fresh_registry }

  it "registers var-backed rules at definition time" do
    described_class.new(name: "spec", set: :size, fn: ->(w, h) { { width: w, height: h } })
    expect(registry.rules.map(&:to_css)).to contain_exactly(
      a_string_matching(/\A\.vc\w+\{width:var\(--vc\w+\)\}\z/),
      a_string_matching(/\A\.vc\w+\{height:var\(--vc\w+\)\}\z/)
    )
  end

  it "returns a style with inline vars when called" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } })
    style = dynamic.call(120)
    expect(style.class_names).to match(/\Avc\w+\z/)
    expect(style.inline_style).to match(/\A--vc\w+:120px\z/)
    expect(registry.size).to eq(1)
  end

  it "returns an empty style for nil or missing args" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } })
    expect(dynamic.call(nil)).to be_empty
    expect(dynamic.call).to be_empty
  end

  it "survives lambdas that do arithmetic on their arguments" do
    dynamic = described_class.new(name: "spec", set: :size, fn: ->(n) { { width: n * 2, opacity: n / 10.0 } })
    expect(registry.size).to eq(2)
    expect(dynamic.call(5).inline_style).to include(":10px").and include(":0.5")
  end

  it "falls back to lazy registration when probing fails" do
    expect do
      dynamic = described_class.new(name: "spec", set: :size, fn: ->(n) { raise "boom" unless Integer === n; { width: n } })
      expect(registry.size).to eq(0)
      dynamic.call(3)
      expect(registry.size).to eq(1)
    end.to output(/Could not probe dynamic style/).to_stderr
  end

  it "is deterministic across instances with the same identity" do
    a = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } }).call(1)
    b = described_class.new(name: "spec", set: :size, fn: ->(w) { { width: w } }).call(1)
    expect(a.class_names).to eq(b.class_names)
    expect(a.inline).to eq(b.inline)
  end
end
