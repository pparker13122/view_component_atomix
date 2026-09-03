# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Style do
  before { with_fresh_registry }

  let(:sheet) do
    ViewComponent::Styles.create(
      a: { color: { default: "red", hover: "pink" }, padding: 4 },
      b: { color: "blue" },
      c: { color: nil }
    )
  end

  it "merges last-wins per property" do
    merged = sheet.a.merge(sheet.b)
    expect(merged.classes.keys).to eq(%w[color padding])
    expect(merged.classes["color"]).to eq(sheet.b.classes["color"])
  end

  it "drops conditional classes when a later style redefines the property" do
    merged = sheet.a.merge(sheet.b)
    expect(merged.class_names.split.length).to eq(2)
  end

  it "unsets a property when merged with nil" do
    merged = sheet.a.merge(sheet.c)
    expect(merged.class_names).to eq(sheet.a.classes["padding"].join)
  end

  it "produces attrs without empty keys" do
    expect(sheet.a.to_attrs.keys).to eq([:class])
    expect(described_class::EMPTY.to_attrs).to eq({})
    expect(described_class::EMPTY.class_names).to be_nil
  end
end
