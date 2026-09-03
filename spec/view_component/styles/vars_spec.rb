# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::Vars do
  let!(:registry) { with_fresh_registry }

  it "registers root vars and exposes var() references" do
    vars = ViewComponent::Styles.define_vars(primary: "#00f", surface: { default: "#fff", dark: "#111" })
    expect(vars.primary).to match(/\Avar\(--vc\w+\)\z/)
    expect(vars[:surface]).to eq("var(#{vars.var_name(:surface)})")
    css = registry.rules.map(&:to_css)
    expect(css).to include(":root{#{vars.var_name(:primary)}:#00f}")
    expect(css).to include("@media (prefers-color-scheme: dark){:root{#{vars.var_name(:surface)}:#111}}")
  end

  it "raises for unknown vars" do
    vars = ViewComponent::Styles.define_vars(primary: "#00f")
    expect { vars[:nope] }.to raise_error(KeyError)
    expect { vars.nope }.to raise_error(NoMethodError)
  end

  it "creates themes that override vars under a class" do
    vars = ViewComponent::Styles.define_vars(primary: "#00f")
    theme = ViewComponent::Styles.create_theme(vars, primary: "red")
    expect(theme.class_names).to match(/\Avc\w+\z/)
    expect(registry.rules.map(&:to_css)).to include(".#{theme.class_names}{#{vars.var_name(:primary)}:red}")
    expect(vars.theme(primary: "red").class_names).to eq(theme.class_names)
  end

  it "makes two themes for the same vars mutually exclusive when merged" do
    vars = ViewComponent::Styles.define_vars(primary: "#00f")
    a = ViewComponent::Styles.create_theme(vars, primary: "red")
    b = ViewComponent::Styles.create_theme(vars, primary: "green")
    expect(ViewComponent::Styles.merge(a, b).class_names).to eq(b.class_names)
  end
end
