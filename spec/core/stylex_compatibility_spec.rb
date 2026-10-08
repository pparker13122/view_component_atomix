# frozen_string_literal: true

RSpec.describe "StyleX compatibility" do
  let!(:registry) { with_fresh_registry }

  it "uses CSS time units and unitless custom properties in static and dynamic styles" do
    sheet = ViewComponent::Atomix.create(
      base: { transition_duration: 200, animation_delay: 0, "--count" => 2 },
      timed: { dynamic: %i[transition_duration], using: ->(time) { { transition_duration: time } } }
    )
    expect(registry.to_css).to include("transition-duration:200ms", "animation-delay:0ms", "--count:2}")
    expect(sheet.timed(0).inline.values).to eq(["0ms"])
    vars = ViewComponent::Atomix.define_vars(weight: 600)
    expect(registry.to_css).to include("#{vars.var_name(:weight)}:600}")
    theme = vars.theme(weight: 700)
    expect(registry.to_css).to include(".#{theme.class_names}{#{vars.var_name(:weight)}:700}")
  end

  it "keeps additional numeric CSS properties unitless" do
    %w[counter-reset mask-border-width shape-image-threshold math-depth].each do |property|
      expect(ViewComponent::Atomix::Property.normalize_value(property, 2)).to eq("2")
    end
  end

  it "evaluates false and nil inputs and lets nil output remove earlier conditions" do
    sheet = ViewComponent::Atomix.create(
      base: { width: { default: 20, hover: 30 } },
      sized: ->(value) { { width: value } },
      toggled: ->(enabled) { { height: enabled ? 20 : 10 } },
      defaulted: ->(value) { { width: value || 15 } }
    )
    expect(ViewComponent::Atomix.props(sheet.base, sheet.sized(nil))).to eq({})
    expect(sheet.toggled(false).inline.values).to eq(["10px"])
    expect(sheet.defaulted(nil).inline.values).to eq(["15px"])
  end

  it "rejects dynamic condition hashes instead of serializing Ruby into CSS" do
    sheet = ViewComponent::Atomix.create(sized: ->(value) { { width: { default: value, hover: 30 } } })
    expect { sheet.sized(10) }.to raise_error(ArgumentError, /cannot use conditions/)
  end

  it "increases specificity once per at-rule and keeps pseudo-elements last" do
    rule = ViewComponent::Atomix::Rule.new(
      selector: ".atom", property: "color", value: "red",
      conditions: ["::before", ":hover", "@media (min-width: 1px)", "@supports (display: grid)"]
    )
    expect(rule.to_css).to include(".atom.atom.atom:hover::before{color:red}")
  end

  it "gives a media condition enough specificity to compete with hover without layers" do
    allow(ViewComponent::Atomix.config).to receive(:use_layers).and_return(false)
    ViewComponent::Atomix.create(base: { color: { hover: "blue", "@media (min-width: 1px)" => "red" } })
    hover, media = registry.rules.sort_by(&:priority)
    expect(hover.to_css).to eq("#{hover.selector}:hover{color:blue}")
    expect(media.to_css).to include("#{media.selector}#{media.selector}{color:red}")
    expect(registry.to_css.index(hover.to_css)).to be < registry.to_css.index(media.to_css)
  end
end
