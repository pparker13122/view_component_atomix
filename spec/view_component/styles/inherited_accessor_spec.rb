# frozen_string_literal: true

RSpec.describe "inherited module accessors" do
  let!(:registry) { with_fresh_registry }

  [false, true].each do |cached|
    [1, 2].each do |depth|
      it "merges inherited traits and vars on rename (cached=#{cached}, depth=#{depth})" do
        shared = Module.new do
          include ViewComponent::Styles
          styles_method :css
          style_vars accent: "red"
          css root: { color: "red" }
        end
        parent = Class.new { include shared }
        parent.styles(parent_trait: { margin: 1 })
        child = depth.times.reduce(parent) { |ancestor, _| Class.new(ancestor) }
        child.styles if cached
        child.styles_method :css
        child.css do
          trait :combined, :root, padding: 2
          trait :local, background: css.accent
        end
        sheet = child.css
        expect(sheet.names).to contain_exactly(:root, :parent_trait, :combined, :local)
        expect(sheet.accent).to eq(shared.css.accent)
        expect(sheet.combined.classes.keys).to contain_exactly("color", "padding")
        expect(child.new.css).to equal(sheet)
        expect(parent.styles.names).to eq([:parent_trait])
        expect(parent.css).to equal(shared.css)

        child.css(root: { color: "blue" })
        expect(child.css.root).not_to eq(shared.css.root)
        expect(parent.css.root).to eq(shared.css.root)
        shared.css(extra: { margin: 4 })
        expect(child.css.names).to include(:extra)
      end
    end
  end

  it "adopts a derived module accessor" do
    stub_const("InheritedPaletteStyles", Module.new do
      include ViewComponent::Styles
      styles root: { color: "red" }
    end)
    parent = Class.new { include InheritedPaletteStyles }
    child = Class.new(parent)
    child.styles_method :inherited_palette_styles
    expect(child.inherited_palette_styles.root).to eq(InheritedPaletteStyles.styles.root)
    expect(child.new.inherited_palette_styles).to equal(child.inherited_palette_styles)
  end

  it "preserves the last separate reader and local module precedence" do
    first = Module.new do
      include ViewComponent::Styles
      styles_method :css
      css first_only: { color: "red" }, root: { color: "red" }
    end
    last = Module.new do
      include ViewComponent::Styles
      styles_method :css
      css last_only: { padding: 2 }, root: { color: "blue" }
    end
    parent = Class.new { include first; include last }
    child = Class.new(parent)
    child.styles_method :css
    expect(child.css.names).to contain_exactly(:last_only, :root)
    expect(child.css.root).to eq(last.css.root)
    child.include(first)
    expect(child.css.root).to eq(first.css.root)
    expect(child.css.names).to include(:last_only, :first_only)
  end

  it "does not reapply modules already merged into an ancestor's primary sheet" do
    shared = Module.new do
      include ViewComponent::Styles
      styles_method :css
      css root: { color: "red" }
    end
    parent = Class.new { include shared }
    parent.styles_method :css
    parent.css(root: { color: "blue" })
    child = Class.new(parent)
    child.styles_method :css
    expect(child.css.root).to eq(parent.css.root)
    expect(child.css.root).not_to eq(shared.css.root)
    child.css(root: { padding: 2 })
    grandchild = Class.new(child)
    grandchild.styles_method :css
    expect(grandchild.css.root).to eq(child.css.root)
  end

  it "keeps companion and owner overrides above an adopted inherited module" do
    shared = Module.new do
      include ViewComponent::Styles
      styles_method :css
      css root: { color: "red" }
    end
    parent = Class.new { include shared }
    stub_const("AccessorChildStyles", Module.new do
      include ViewComponent::Styles
      styles root: { color: "blue" }
    end)
    stub_const("AccessorChild", Class.new(parent))
    AccessorChild.styles_method :css
    expect(AccessorChild.css.root).to eq(AccessorChildStyles.styles.root)
    AccessorChild.css(root: { padding: 2 })
    expect(AccessorChild.css.root.classes.keys).to eq(["padding"])
    expect(parent.css.root).to eq(shared.css.root)
  end
end
