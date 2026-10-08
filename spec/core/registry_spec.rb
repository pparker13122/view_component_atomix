# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::Registry do
  let!(:registry) { with_fresh_registry }

  it "dedupes identical rules" do
    ViewComponent::Atomix.create(a: { color: "red" })
    ViewComponent::Atomix.create(b: { color: "red" })
    expect(registry.size).to eq(1)
  end

  it "emits rules sorted by priority so longhands beat shorthands without layers" do
    ViewComponent::Atomix.create(a: { padding_top: 1, padding: 2, color: { active: "a", hover: "h" } })
    css = registry.to_css
    expect(css).not_to include("@layer")
    expect(css.lines.length).to eq(4)
    expect(css.index("padding:2px")).to be < css.index("padding-top:1px")
    expect(css.index(":hover{color:h}")).to be < css.index(":active{color:a}")
  end

  it "can wrap rules in cascade layers" do
    allow(ViewComponent::Atomix.config).to receive(:use_layers).and_return(true)
    ViewComponent::Atomix.config.class_prefix = "zz"
    ViewComponent::Atomix.create(a: { padding_top: 1, padding: 2, color: { active: "a", hover: "h" } })
    expect(registry.to_css.lines.map(&:chomp)).to match([
      "@layer zz1000,zz4000,zz4130,zz4170;",
      "@layer zz1000{", a_string_matching(/\A\.zz\w+\{padding:2px\}\z/), "}",
      "@layer zz4000{", a_string_matching(/\A\.zz\w+\{padding-top:1px\}\z/), "}",
      "@layer zz4130{", a_string_matching(/\A\.zz\w+:hover\{color:h\}\z/), "}",
      "@layer zz4170{", a_string_matching(/\A\.zz\w+:active\{color:a\}\z/), "}"
    ])
  end

  it "invalidates the cached css when rules are added" do
    ViewComponent::Atomix.create(a: { color: "red" })
    first = registry.to_css
    ViewComponent::Atomix.create(a: { color: "blue" })
    expect(registry.to_css).not_to eq(first)
    registry.clear
    expect(registry.to_css).to eq("")
  end
end

RSpec.describe "shorthand cascade ordering" do
  # Parent/child relationships, including shorthand children and logical sides.
  # Values are only used to distinguish the emitted declarations.
  relationships = {
    "all" => %w[animation background border font grid inset margin mask padding],
    "border" => %w[border-block border-inline border-top border-right border-bottom border-left],
    "border-block" => %w[border-block-color border-block-style border-block-width border-block-start border-block-end],
    "border-inline" => %w[border-inline-color border-inline-style border-inline-width border-inline-start border-inline-end],
    "border-top" => %w[border-top-color border-top-style border-top-width],
    "border-right" => %w[border-right-color border-right-style border-right-width],
    "border-bottom" => %w[border-bottom-color border-bottom-style border-bottom-width],
    "border-left" => %w[border-left-color border-left-style border-left-width],
    "border-block-color" => %w[border-block-start-color border-block-end-color],
    "border-block-style" => %w[border-block-start-style border-block-end-style],
    "border-block-width" => %w[border-block-start-width border-block-end-width],
    "border-inline-color" => %w[border-inline-start-color border-inline-end-color],
    "border-inline-style" => %w[border-inline-start-style border-inline-end-style],
    "border-inline-width" => %w[border-inline-start-width border-inline-end-width],
    "grid" => %w[grid-template grid-auto-flow],
    "grid-template" => %w[grid-template-areas grid-template-columns grid-template-rows],
    "grid-area" => %w[grid-row grid-column],
    "grid-row" => %w[grid-row-start grid-row-end],
    "font" => %w[font-variant font-size],
    "font-variant" => %w[font-variant-caps],
    "font-synthesis" => %w[font-synthesis-weight font-synthesis-style font-synthesis-small-caps],
    "text-wrap" => %w[text-wrap-mode text-wrap-style],
    "white-space" => %w[white-space-collapse text-wrap-mode],
    "text-box" => %w[text-box-trim text-box-edge],
    "position-try" => %w[position-try-order position-try-fallbacks],
    "mask" => %w[mask-border mask-image],
    "mask-border" => %w[mask-border-source mask-border-width],
    "background" => %w[background-position background-color],
    "background-position" => %w[background-position-x background-position-y],
    "animation" => %w[animation-range animation-name],
    "animation-range" => %w[animation-range-start animation-range-end],
    "padding" => %w[padding-inline padding-block padding-top],
    "padding-inline" => %w[padding-inline-start padding-inline-end],
    "margin" => %w[margin-inline margin-block margin-top],
    "margin-block" => %w[margin-block-start margin-block-end],
    "inset" => %w[inset-inline inset-block top],
    "inset-block" => %w[inset-block-start inset-block-end]
  }

  def cascade_position(css, declaration, layers)
    return css.index(declaration) unless layers

    order = css[/\A@layer ([^;]+);/, 1].split(",")
    layer, = css.scan(/^@layer ([^{;]+)\{\n(.*?)\n\}$/m).find { |_, rules| rules.include?(declaration) }
    order.index(layer)
  end

  [false, true].each do |layers|
    it "places constituent properties after their shorthands regardless of registration order (layers=#{layers})" do
      registry = with_fresh_registry
      allow(ViewComponent::Atomix.config).to receive(:use_layers).and_return(layers)
      relationships.each do |shorthand, children|
        children.each do |longhand|
          [[shorthand, longhand], [longhand, shorthand]].each do |order|
            registry.clear
            ViewComponent::Atomix.create(root: order.to_h { |property| [property, "initial"] })
            css = registry.to_css
            expect(cascade_position(css, "#{shorthand}:initial", layers))
              .to be < cascade_position(css, "#{longhand}:initial", layers),
                  "Expected #{shorthand} before #{longhand}, got #{css}"
          end
        end
      end
    end
  end
end

RSpec.describe "registry transaction boundaries" do
  let(:registry) { ViewComponent::Atomix::Registry.new }

  def rule(value)
    ViewComponent::Atomix::Rule.new(selector: ".#{value}", property: "color", value: value)
  end

  it "publishes nested rules before running callbacks in registration order" do
    calls = []
    registry.transaction do
      registry.add(rule("red"))
      registry.after_commit { calls << [:outer, registry.size] }
      registry.transaction do
        registry.add(rule("blue"))
        registry.after_commit { calls << [:inner, registry.size] }
      end
      expect(registry.size).to eq(0)
      expect(calls).to be_empty
    end
    expect(calls).to eq([[:outer, 2], [:inner, 2]])
  end

  it "retains independently committed rules and callbacks when the outer declaration fails" do
    calls = []
    expect do
      registry.transaction do
        registry.add(rule("red"))
        registry.after_commit { calls << :outer }
        registry.transaction(independent: true) do
          registry.add(rule("blue"))
          registry.after_commit { calls << :independent }
        end
        raise "failed"
      end
    end.to raise_error("failed")
    expect(registry.rules.map(&:value)).to eq(["blue"])
    expect(calls).to eq([:independent])
    registry.transaction { registry.add(rule("green")) }
    expect(registry.rules.map(&:value)).to eq(%w[blue green])
  end
end
