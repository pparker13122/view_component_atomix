# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Variables, type: :component do
  let!(:registry) { with_fresh_registry }

  it "invalidates cached descendants when parent variables are extended" do
    parent = Class.new do
      include ViewComponent::Styles
      style_vars accent: "red"
    end
    child = Class.new(parent)
    grandchild = Class.new(child)
    expect(grandchild.styles.var_names).to eq([:accent])
    parent.style_vars gap: 8
    expect(grandchild.styles.gap).to eq(parent.styles.gap)
    parent.style_vars { { gutter: 12 } }
    expect(grandchild.styles.gutter).to eq(parent.styles.gutter)
  end

  it "retries variable blocks after an evaluation failure" do
    ready = false
    klass = Class.new do
      include ViewComponent::Styles::Variables
      style_vars do
        raise "not ready" unless ready
        { gap: 8 }
      end
    end
    2.times { expect { klass.styles }.to raise_error("not ready") }
    ready = true
    expect(klass.styles.var_names).to eq([:gap])
  end

  it "declares vars readable through styles and emits them on :root" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      style_vars gap: 12, accent: "#f60"
      styles root: { gap: styles.gap, color: styles.accent }
    end

    expect(klass.styles.gap).to match(/\Avar\(--vc\w+\)\z/)
    expect(klass.styles[:accent]).to eq(klass.styles.accent)
    expect(klass.styles.var_names).to eq(%i[gap accent])
    expect(klass.new.styles.accent).to eq(klass.styles.accent)
    expect(registry.to_css).to include(":root{#{klass.styles.vars_for(:gap).var_name(:gap)}:12px}")
    expect(registry.to_css).to include("{gap:#{klass.styles.gap}}")
  end

  it "supports the block form, merges repeated calls and shadows configured vars" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      style_vars { { primary: "red" } }
      style_vars gap: 4
    end

    expect(klass.styles.var_names).to contain_exactly(:primary, :gap)
    expect(klass.styles.primary).not_to eq(Brand::VARS.primary)
    expect(klass.styles.surface).to eq(Brand::VARS.surface)
    expect(klass.styles).not_to be_empty
  end

  it "falls back to configured vars without adding them to the sheet" do
    klass = Class.new(ViewComponent::Base) { include ViewComponent::Styles }
    expect(klass.styles).to be_empty
    expect(klass.styles.primary).to eq(Brand::VARS.primary)
    expect(klass.styles.key?(:primary)).to be(true)
    expect(klass.styles.respond_to?(:primary)).to be(true)
    expect { klass.styles.nope }.to raise_error(NoMethodError)
  end

  it "is inherited and can be overridden in subclasses" do
    parent = stub_const("VarsParentComponent", Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      style_vars gap: 4, accent: "red"
    end)
    child = Class.new(parent) { style_vars accent: "blue" }

    expect(child.styles.gap).to eq(parent.styles.gap)
    expect(child.styles.accent).not_to eq(parent.styles.accent)
  end

  it "requires a Hash or block" do
    klass = Class.new(ViewComponent::Base) { include ViewComponent::Styles }
    expect { klass.style_vars }.to raise_error(ArgumentError, /Hash or a block/)
  end

  describe "included on its own" do
    it "provides style_vars and the styles reader but not style sets" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles::Variables
        style_vars gap: 8
      end

      expect(klass.styles.gap).to match(/\Avar\(/)
      expect(klass.new.styles.gap).to eq(klass.styles.gap)
      expect(klass).not_to respond_to(:theme)
      expect { klass.styles(base: { color: "red" }) }.to raise_error(ArgumentError, /Include ViewComponent::Styles/)
    end

    it "respects styles_method" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles::Variables
        styles_method :vars
        style_vars gap: 8
      end

      expect(klass.vars.gap).to match(/\Avar\(/)
      expect(klass).not_to respond_to(:styles)
    end
  end

  describe "in a shared module" do
    it "is exposed under the module's base name plus _styles" do
      stub_const("BrandVars", Module.new do
        include ViewComponent::Styles::Variables
        style_vars accent: "#f60"
      end)
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        include BrandVars
        styles root: { color: brand_styles.accent }
      end

      expect(klass.brand_styles.accent).to eq(BrandVars.styles.accent)
      expect(klass.new.brand_styles.accent).to eq(BrandVars.styles.accent)
      expect(klass.styles.var_names).to be_empty
      expect(klass.styles.root.classes["color"]).to eq(
        ViewComponent::Styles.create(x: { color: BrandVars.styles.accent }).x.classes["color"]
      )
    end

    it "merges an explicit styles_method into the component's sheet" do
      stub_const("SpacingVars", Module.new do
        include ViewComponent::Styles::Variables
        styles_method :styles
        style_vars gutter: 16
      end)
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        include SpacingVars
        styles root: { padding: styles.gutter }
      end

      expect(klass.styles.var_names).to eq(%i[gutter])
      expect(klass.styles.names).to eq(%i[root])
    end
  end
end
