# frozen_string_literal: true

RSpec.describe "value ownership" do
  let(:styles) { ViewComponent::Styles }
  let!(:registry) { with_fresh_registry }

  it "protects styles and merged styles from caller mutations without freezing caller data" do
    class_name = +"original"
    value = +"10px"
    classes = { "width" => [class_name] }
    inline = { "--width" => value }
    style = styles::Style.new(classes, inline)
    merged = style.merge(styles::Style.new("color" => ["red"]))
    original_hash = style.hash

    class_name.replace("changed")
    classes["width"] << "extra"
    value.replace("20px")
    inline.clear

    expect(style.class_names).to eq("original")
    expect(merged.class_names).to eq("original red")
    expect(style.inline_style).to eq("--width:10px")
    expect(style.hash).to eq(original_hash)
    expect { style.classes["width"] << "extra" }.to raise_error(FrozenError)
    expect { style.classes["width"].first.replace("other") }.to raise_error(FrozenError)
    expect { style.inline["--width"].replace("other") }.to raise_error(FrozenError)
  end

  it "keeps registered rule identity and cached CSS stable when inputs change" do
    selector = +".example"
    property = +"display"
    value = +"grid"
    condition = +":hover"
    values = [value]
    conditions = [condition]
    rule = styles::Rule.new(selector: selector, property: property, value: values, conditions: conditions)
    registry.add(rule)
    css = registry.to_css

    [selector, property, value, condition].each { |input| input.replace("changed") }
    values << "flex"
    conditions.clear
    expect(rule.to_css).to eq(".example:hover{display:grid}")
    expect(registry.to_css).to eq(css)
    registry.add(styles::Rule.new(selector: ".example", property: "display", value: ["grid"], conditions: [":hover"]))
    expect(registry.size).to eq(1)
    expect { rule.value << "flex" }.to raise_error(FrozenError)
    expect { rule.conditions.first.replace(":focus") }.to raise_error(FrozenError)
  end

  it "owns variable identifiers and references" do
    id = +"palette"
    vars = styles::Vars.new(id, accent: "red")
    id.replace("changed")
    expect(vars.id).to eq("palette")
    expect { vars.accent.replace("other") }.to raise_error(FrozenError)
    expect { vars.var_name(:accent).replace("other") }.to raise_error(FrozenError)
  end

  it "copies sheet and member maps while retaining callable style objects" do
    member = styles::Style.new("color" => ["red"])
    members = { red: member }
    enumerated = styles::EnumeratedStyle.new(name: :tone, members: members)
    sets = { tone: enumerated }
    sheet = styles::Sheet.new(sets)
    members.clear
    sets.clear
    expect(sheet.tone(:red)).to equal(member)
    expect(sheet[:tone]).to equal(enumerated)
  end
end
