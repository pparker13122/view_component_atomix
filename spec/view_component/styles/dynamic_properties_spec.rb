# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::DynamicProperties do
  it "extracts static keys without executing value expressions" do
    called = false
    fn = ->(x) { { width: x, opacity: (called = true) } }

    expect(described_class.extract(fn, name: "Spec", set: :box)).to eq(%w[width opacity])
    expect(called).to be(false)
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
