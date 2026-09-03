# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Sheet do
  before { with_fresh_registry }

  let(:sheet) { ViewComponent::Styles.create(base: { color: "red" }, sized: ->(w) { { width: w } }) }

  it "exposes sets as methods and via []" do
    expect(sheet.base).to equal(sheet[:base])
    expect(sheet.respond_to?(:base)).to be(true)
  end

  it "calls dynamic sets with arguments" do
    expect(sheet.sized(10).inline_style).to end_with(":10px")
    expect(sheet.fetch(:sized, 10)).to eq(sheet.sized(10))
  end

  it "returns nil for a nil lookup so conditionals can be skipped" do
    expect(sheet[nil]).to be_nil
  end

  it "raises for unknown sets" do
    expect { sheet[:nope] }.to raise_error(KeyError, /Available sets: \[:base, :sized\]/)
    expect { sheet.nope }.to raise_error(NoMethodError)
  end

  it "rejects arguments on static sets" do
    expect { sheet.base(1) }.to raise_error(ArgumentError, /static/)
  end

  it "merges with later sets winning" do
    other = ViewComponent::Styles.create(base: { color: "blue" }, extra: { padding: 1 })
    merged = sheet.merge(other)
    expect(merged.names).to eq(%i[base sized extra])
    expect(merged.base).to equal(other.base)
    expect(sheet.names).to eq(%i[base sized])
  end
end
