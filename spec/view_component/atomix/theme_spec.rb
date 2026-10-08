# frozen_string_literal: true

require "rails_helper"

RSpec.describe ViewComponent::Atomix::Theme, type: :component do
  let!(:registry) { with_fresh_registry }

  def theme_rule(style, vars, key, value)
    ".#{style.classes["theme:#{vars.id}"].join}{#{vars.var_name(key)}:#{value}}"
  end

  it "declares overrides against configured vars and exposes them through theme" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      theme primary: "#000"
    end

    expect(klass.theme).to be_a(ViewComponent::Atomix::Style)
    expect(klass.new.theme).to equal(klass.theme)
    expect(registry.to_css).to include(theme_rule(klass.theme, Brand::VARS, :primary, "#000"))
  end

  it "resolves keys against the component's own vars first and groups by owner" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      style_vars accent: "#f60", surface: "#eee"
      theme accent: "#0c6", surface: "#222", primary: "#000"
    end

    own = klass.styles.vars_for(:accent)
    expect(klass.theme.classes.keys).to contain_exactly("theme:#{own.id}", "theme:#{Brand::VARS.id}")
    expect(registry.to_css).to include(theme_rule(klass.theme, own, :accent, "#0c6"))
    expect(registry.to_css).to include(theme_rule(klass.theme, own, :surface, "#222"))
    expect(registry.to_css).not_to include("#{Brand::VARS.var_name(:surface)}:#222")
    expect(registry.to_css).to include(theme_rule(klass.theme, Brand::VARS, :primary, "#000"))
  end

  it "accepts an explicit Vars object, a block, and merges repeated calls" do
    other = ViewComponent::Atomix.define_vars(name: "other", tint: "red")
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      theme other, tint: "blue"
      theme { { primary: "#111" } }
    end

    expect(klass.theme.classes.keys).to contain_exactly("theme:other", "theme:#{Brand::VARS.id}")
    expect(registry.to_css).to include(theme_rule(klass.theme, other, :tint, "blue"))
  end

  it "raises for unknown keys and non-Vars positional arguments" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      theme nope: "x"
    end
    2.times { expect { klass.theme }.to raise_error(KeyError, /Unknown var :nope/) }
    expect { klass.theme("x", primary: "y") }.to raise_error(ArgumentError, /Vars object/)
  end

  it "returns an empty style when nothing is declared" do
    klass = Class.new(ViewComponent::Base) { include ViewComponent::Atomix }
    expect(klass.theme).to be_empty
    expect(ViewComponent::Atomix.sx(klass.theme)).to eq("")
  end

  it "is inherited, with the subclass winning for the same vars" do
    other = ViewComponent::Atomix.define_vars(name: "other", tint: "red")
    parent = stub_const("ThemeParentComponent", Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      theme primary: "#000"
      theme other, tint: "blue"
    end)
    plain = Class.new(parent)
    child = Class.new(parent) { theme primary: "#fff" }

    expect(child.theme.classes).not_to eq(parent.theme.classes)
    expect(registry.to_css).to include(theme_rule(child.theme, Brand::VARS, :primary, "#fff"))

    retained = ViewComponent::Atomix.create_theme(other, tint: "blue")
    expect(plain.theme).to eq(
      ViewComponent::Atomix.merge(retained, ViewComponent::Atomix.create_theme(Brand::VARS, primary: "#000"))
    )
    expect(child.theme).to eq(
      ViewComponent::Atomix.merge(retained, ViewComponent::Atomix.create_theme(Brand::VARS, primary: "#fff"))
    )
  end

  describe "included on its own" do
    it "provides theme without styles" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix::Theme
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
      own = ViewComponent::Atomix.create_theme(PanelComponent.styles.vars_for(:accent), accent: "#00cc66")
      expect(PanelComponent.theme).to eq(own)
      expect(PanelComponent.theme.class_names.split).not_to include(*DarkModeTheme.theme.class_names.split)
    end

    it "strips Style, Styles, Theme, Vars and Variables suffixes" do
      %w[Style Styles Theme Vars Variables].each do |suffix|
        mod = stub_const("HighContrast#{suffix}", Module.new do
          include ViewComponent::Atomix
          styles root: { color: "white" }
          theme primary: "#fff"
        end)
        klass = Class.new(ViewComponent::Base) { include mod }

        expect(klass.high_contrast_styles.root).to equal(mod.styles.root)
        expect(klass.high_contrast_theme).to equal(mod.theme)
        expect(klass).not_to respond_to(:"high_contrast_#{suffix.downcase}_styles")
      end
    end

    it "merges an anonymous module's theme into theme" do
      other = ViewComponent::Atomix.define_vars(name: "other", tint: "red")
      anonymous = Module.new do
        include ViewComponent::Atomix::Theme
        theme other, tint: "blue"
        theme primary: "#abc"
      end
      klass = Class.new(ViewComponent::Base) do
        include anonymous
        theme surface: "#def"
      end

      expect(klass.theme.classes.keys).to contain_exactly("theme:other", "theme:#{Brand::VARS.id}")
      expect(registry.to_css).to include(theme_rule(klass.theme, other, :tint, "blue"))
      expect(registry.to_css).to include(theme_rule(anonymous.theme, Brand::VARS, :primary, "#abc"))
      expect(klass.theme).to eq(
        ViewComponent::Atomix.merge(
          ViewComponent::Atomix.create_theme(other, tint: "blue"),
          ViewComponent::Atomix.create_theme(Brand::VARS, surface: "#def")
        )
      )
    end

    it "renders a module theme on a component" do
      render_inline(PanelComponent.new(dark: true)) { "x" }
      section = page.find("section")
      expect(section[:class].split).to include(DarkModeTheme.theme.class_names)
      expect(section[:class].split).to include(*PanelComponent.styles.root.class_names.split)

      render_inline(PanelComponent.new) { "y" }
      plain = page.find("section")[:class].split
      own = ViewComponent::Atomix.create_theme(PanelComponent.styles.vars_for(:accent), accent: "#00cc66")
      expect(plain).to include(own.class_names)
      expect(plain).not_to include(DarkModeTheme.theme.class_names)
    end

    it "is compiled on eager load" do
      expect(ViewComponent::Atomix.includers).to include(DarkModeTheme, PanelComponent)
      stub_const("LazyTheme", Module.new do
        include ViewComponent::Atomix::Theme
        theme { { surface: "#010101" } }
      end)
      Class.new(ViewComponent::Base) { include LazyTheme }

      css = ViewComponent::Atomix.eager_load!.to_css
      expect(css).to include(theme_rule(LazyTheme.theme, Brand::VARS, :surface, "#010101"))
    end
  end
end
