# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Theme, type: :component do
  let!(:registry) { with_fresh_registry }

  def theme_rule(style, vars, key, value)
    ".#{style.classes["theme:#{vars.id}"].join}{#{vars.var_name(key)}:#{value}}"
  end

  it "declares overrides against configured vars and exposes them through theme" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      theme primary: "#000"
    end

    expect(klass.theme).to be_a(ViewComponent::Styles::Style)
    expect(klass.new.theme).to equal(klass.theme)
    expect(registry.to_css).to include(theme_rule(klass.theme, Brand::VARS, :primary, "#000"))
  end

  it "resolves keys against the component's own vars first and groups by owner" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      style_vars accent: "#f60"
      theme accent: "#0c6", primary: "#000"
    end

    own = klass.styles.vars_for(:accent)
    expect(klass.theme.classes.keys).to contain_exactly("theme:#{own.id}", "theme:#{Brand::VARS.id}")
    expect(registry.to_css).to include(theme_rule(klass.theme, own, :accent, "#0c6"))
    expect(registry.to_css).to include(theme_rule(klass.theme, Brand::VARS, :primary, "#000"))
  end

  it "accepts an explicit Vars object, a block, and merges repeated calls" do
    other = ViewComponent::Styles.define_vars(name: "other", tint: "red")
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      theme other, tint: "blue"
      theme { { primary: "#111" } }
    end

    expect(klass.theme.classes.keys).to contain_exactly("theme:other", "theme:#{Brand::VARS.id}")
    expect(registry.to_css).to include(theme_rule(klass.theme, other, :tint, "blue"))
  end

  it "raises for unknown keys and non-Vars positional arguments" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      theme nope: "x"
    end
    2.times { expect { klass.theme }.to raise_error(KeyError, /Unknown var :nope/) }
    expect { klass.theme("x", primary: "y") }.to raise_error(ArgumentError, /Vars object/)
  end

  it "returns an empty style when nothing is declared" do
    klass = Class.new(ViewComponent::Base) { include ViewComponent::Styles }
    expect(klass.theme).to be_empty
    expect(ViewComponent::Styles.sx(klass.theme)).to eq("")
  end

  it "is inherited, with the subclass winning for the same vars" do
    parent = stub_const("ThemeParentComponent", Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      theme primary: "#000"
    end)
    child = Class.new(parent) { theme primary: "#fff" }

    expect(child.theme.classes).not_to eq(parent.theme.classes)
    expect(registry.to_css).to include(theme_rule(child.theme, Brand::VARS, :primary, "#fff"))
  end

  describe "included on its own" do
    it "provides theme without styles" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles::Theme
        theme primary: "#000"
      end

      expect(klass.theme).not_to be_empty
      expect(klass.new.theme).to equal(klass.theme)
      expect(klass).not_to respond_to(:styles)
      expect(klass.new).not_to respond_to(:styles)
    end
  end

  describe "in a shared module" do
    it "is exposed as <base>_theme at class and instance level" do
      expect(PanelComponent.dark_mode_theme).to equal(DarkModeTheme.theme)
      expect(PanelComponent.new.dark_mode_theme).to equal(DarkModeTheme.theme)
      expect(PanelComponent.theme).not_to equal(DarkModeTheme.theme)
    end

    it "strips Style, Styles, Theme, Vars and Variables suffixes" do
      stub_const("DarkModeStyle", Module.new do
        include ViewComponent::Styles
        styles root: { color: "white" }
        theme primary: "#fff"
      end)
      klass = Class.new(ViewComponent::Base) { include DarkModeStyle }

      expect(klass.dark_mode_styles.root).to equal(DarkModeStyle.styles.root)
      expect(klass.dark_mode_theme).to equal(DarkModeStyle.theme)
      expect(klass).not_to respond_to(:dark_mode_style)
    end

    it "merges an anonymous module's theme into theme" do
      anonymous = Module.new do
        include ViewComponent::Styles::Theme
        theme primary: "#abc"
      end
      klass = Class.new(ViewComponent::Base) do
        include anonymous
        theme surface: "#def"
      end

      expect(klass.theme.classes.keys).to eq(["theme:#{Brand::VARS.id}"])
      expect(registry.to_css).to include(theme_rule(anonymous.theme, Brand::VARS, :primary, "#abc"))
    end

    it "renders a module theme on a component" do
      render_inline(PanelComponent.new(dark: true)) { "x" }
      section = page.find("section")
      expect(section[:class].split).to include(DarkModeTheme.theme.class_names)
      expect(section[:class].split).to include(*PanelComponent.styles.root.class_names.split)

      render_inline(PanelComponent.new) { "y" }
      expect(page.find("section")[:class].split).to include(*PanelComponent.theme.class_names.split)
    end

    it "is compiled on eager load" do
      expect(ViewComponent::Styles.includers).to include(DarkModeTheme, PanelComponent)
      stub_const("LazyTheme", Module.new do
        include ViewComponent::Styles::Theme
        theme { { surface: "#010101" } }
      end)
      Class.new(ViewComponent::Base) { include LazyTheme }

      css = ViewComponent::Styles.eager_load!.to_css
      expect(css).to include(theme_rule(LazyTheme.theme, Brand::VARS, :surface, "#010101"))
    end
  end
end
