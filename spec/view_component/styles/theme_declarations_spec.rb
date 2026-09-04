# frozen_string_literal: true

RSpec.describe "theme declarations" do
  let(:styles) { ViewComponent::Styles }
  let!(:registry) { with_fresh_registry }

  it "refreshes inherited themes after a parent declaration" do
    vars = styles.define_vars(name: "theme-cache", accent: "red")
    parent = Class.new { include ViewComponent::Styles }
    parent.theme(vars, accent: "blue")
    child = Class.new(parent)
    old = child.theme
    parent.theme(vars, accent: "green")
    expect(child.theme).to eq(parent.theme)
    expect(child.theme).not_to eq(old)
  end

  it "replaces an inherited theme for the same variable set while retaining other sets" do
    palette = styles.define_vars(name: "palette", accent: "red", surface: "white")
    spacing = styles.define_vars(name: "spacing", gap: 2)
    parent = Class.new { include ViewComponent::Styles }
    parent.theme(palette, accent: "blue", surface: "black")
    parent.theme(spacing, gap: 4)
    child = Class.new(parent)
    child.theme(palette, accent: "green")
    expected = styles.merge(styles.create_theme(palette, accent: "green"), styles.create_theme(spacing, gap: 4))
    expect(child.theme).to eq(expected)
    expect(child.theme.class_names.split).not_to include(parent.theme.classes.fetch("theme:palette").first)
  end

  it "keeps all overrides across separate variable declarations in either key order" do
    stub_const("SplitThemeComponent", Class.new)
    SplitThemeComponent.class_eval do
      include ViewComponent::Styles
      style_vars accent: "red"
      style_vars surface: "white"
    end
    owner = SplitThemeComponent
    [{ accent: "blue", surface: "black" }, { surface: "black", accent: "blue" }].each do |overrides|
      owner.theme(**overrides)
      selected = owner.theme.class_names.split.map { |name| ".#{name}" }
      expect(selected.size).to eq(1)
      rules = registry.rules.select { |rule| selected.include?(rule.selector) }
      expect(rules.map { |rule| [rule.property, rule.value] }).to contain_exactly(
        [owner.styles.vars_for(:accent).var_name(:accent), "blue"],
        [owner.styles.vars_for(:surface).var_name(:surface), "black"]
      )
    end
  end
end
