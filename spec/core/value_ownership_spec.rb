# frozen_string_literal: true

RSpec.describe "value ownership" do
  let(:styles) { ViewComponent::Atomix }
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
    registry.add(styles::Rule.new(selector: ".example", property: "display", value: ["grid"], conditions: [":hover"]))
    expect(registry.size).to eq(1)
    registry.add(styles::Rule.new(selector: ".other", property: "color", value: "red"))
    expect(registry.to_css).to include(css)
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

  [false, true].each do |inline|
    [false, true].each do |compile_first|
      it "owns dynamic names across build and runtime (inline=#{inline}, compiled=#{compile_first})" do
        allow(styles.config).to receive(:inline?).and_return(inline)
        name = +"owned-dynamic"
        fn = ->(value) { { width: value } }
        sheet = styles.create(name: name, box: { dynamic: [:width], using: fn })
        sheet[:box].compile! if compile_first
        name.replace("changed")
        sheet[:box].compile!

        runtime = styles.create(name: "owned-dynamic", box: { dynamic: [:width], using: fn })
        expect(sheet.box(12)).to eq(runtime.box(12))
        expect(sheet[:box].name).to eq("owned-dynamic")
        expect(sheet[:box].name).to be_frozen
        expect(registry.to_css)
          .to include(".#{runtime.box(12).class_names}{width:var(#{runtime.box(12).inline.keys.first})}")
      end

      it "owns dynamic property strings without freezing caller inputs (inline=#{inline}, compiled=#{compile_first})" do
        allow(styles.config).to receive(:inline?).and_return(inline)
        properties = [+"width", +"--gap"]
        value = 12
        fn = -> { { width: value, "--gap" => value } }
        sheet = styles.create(name: "owned-properties", box: { dynamic: properties, using: fn })
        sheet[:box].compile! if compile_first
        properties.each { |property| property.replace("changed") }
        properties.clear
        sheet[:box].compile!

        rendered = sheet.box
        expect(rendered.classes.keys).to eq(["width", "--gap"])
        rendered.classes.zip(rendered.inline.keys).each do |(property, names), var|
          expect(registry.rules).to include(
            have_attributes(selector: ".#{names.first}", property: property, value: "var(#{var})")
          )
        end
        value = 20
        expect(sheet.box.inline.values).to eq(["20px", "20"])
      end
    end
  end
end
