# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Compiler do
  let!(:registry) { with_fresh_registry }

  def compile(**defs)
    described_class.compile(defs, name: "spec")
  end

  it "returns a sheet with one style per set" do
    sheet = compile(base: { color: "red" }, other: { padding: 4 })
    expect(sheet.names).to eq(%i[base other])
    expect(sheet.base).to be_a(ViewComponent::Styles::Style)
  end

  it "registers one atomic rule per property value" do
    compile(base: { color: "red", padding: 4 })
    expect(registry.rules.map(&:to_css)).to contain_exactly(
      a_string_matching(/\A\.vc\w+\{color:red\}\z/),
      a_string_matching(/\A\.vc\w+\{padding:4px\}\z/)
    )
  end

  it "keeps all conditions of a property under one merge key" do
    sheet = compile(base: { color: { default: "red", hover: "blue", md: "green" } })
    expect(sheet.base.classes.keys).to eq(["color"])
    expect(sheet.base.classes["color"].length).to eq(3)
    css = registry.rules.map(&:to_css)
    expect(css).to include(a_string_matching(/:hover\{color:blue\}/))
    expect(css).to include(a_string_matching(/\A@media \(max-width: 768px\)\{\.vc\w+\{color:green\}\}\z/))
  end

  it "supports nested conditions" do
    compile(base: { color: { md: { hover: "blue" } } })
    expect(registry.rules.first.to_css).to match(/\A@media \(max-width: 768px\)\{\.vc\w+:hover\{color:blue\}\}\z/)
    expect(registry.rules.first.priority).to eq(4000 + 200 + 130)
  end

  it "prefixes bare breakpoint queries with @media" do
    allow(ViewComponent::Styles.config).to receive(:breakpoints).and_return({ sm: "(max-width: 600px)" })
    compile(base: { color: { sm: "red" } })
    expect(registry.rules.first.to_css).to start_with("@media (max-width: 600px){")
  end

  it "accepts raw string conditions" do
    compile(base: { color: { ":nth-child(2)" => "red", "@supports (display: grid)" => "blue" } })
    css = registry.rules.map(&:to_css)
    expect(css).to include(a_string_matching(/:nth-child\(2\)\{color:red\}/))
    expect(css).to include(a_string_matching(/\A@supports \(display: grid\)\{/))
  end

  it "supports pseudo-element blocks" do
    sheet = compile(base: { before: { content: '""', display: "block" } })
    expect(sheet.base.classes.keys).to eq(%w[::beforecontent ::beforedisplay])
    expect(registry.rules.map(&:to_css)).to include(a_string_matching(/::before\{content:""\}/))
  end

  it "allows pseudo-elements inside enumerated members" do
    sheet = compile(size: { sm: { font_size: 14, before: { content: '""' } }, lg: { font_size: 20 } })

    expect(sheet.size(:sm).classes.keys).to contain_exactly("font-size", "::beforecontent")
  end

  it "rejects a hash-valued enumerated default" do
    expect { compile(size: { default: { font_size: 14 }, sm: { font_size: 12 } }) }
      .to raise_error(ArgumentError, /must name a member/)
  end

  it "emits fallback declarations for arrays" do
    compile(base: { position: %w[sticky fixed] })
    expect(registry.rules.first.to_css).to match(/\{position:sticky;position:fixed\}/)
  end

  it "treats nil as unset" do
    sheet = compile(base: { color: nil })
    expect(sheet.base.classes).to eq({ "color" => nil })
    expect(registry.size).to eq(0)
  end

  it "rejects unknown symbol conditions" do
    expect { compile(base: { color: { bogus: "red" } }) }
      .to raise_error(ArgumentError, /Unknown style condition :bogus/)
  end

  it "explains when an unknown property is interpreted as an enumerated member" do
    expect { compile(base: { colour: { hover: "red" } }) }
      .to raise_error(ArgumentError, /member :colour.*trait :base.*check its spelling/)
  end

  it "rejects top-level conditions" do
    expect { compile(base: { hover: { color: "red" } }) }
      .to raise_error(ArgumentError, /nested under a property/)
  end

  it "rejects non-hash sets" do
    expect { compile(base: "nope") }.to raise_error(ArgumentError, /must be a Hash or a lambda/)
  end

end
