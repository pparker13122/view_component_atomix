# frozen_string_literal: true

require "rails_helper"

RSpec.describe "complete root variable replacement" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  [false, true].each do |deferred|
    it "replaces the entire conditional assignment through style_vars (deferred=#{deferred})" do
      owner = Class.new { include ViewComponent::Atomix }
      declare = lambda do |value|
        if deferred
          owner.style_vars(name: "replacement") { { accent: value } }
        else
          owner.style_vars(name: "replacement", accent: value)
        end
        owner.styles.vars_for(:accent).var_name(:accent)
      end
      replacements = [
        ["blue", [["blue", []]]],
        [{ dark: "green" }, [["green", ["@media (prefers-color-scheme: dark)"]]]],
        [{ default: "blue", dark: nil }, [["blue", []]]],
        [{ print: { dark: "gray" } }, [["gray", ["@media print", "@media (prefers-color-scheme: dark)"]]]],
        [{}, []],
        [nil, []]
      ]
      replacements.each do |replacement, expected|
        declare.call(default: "red", dark: "black")
        variable = declare.call(replacement)
        rules = registry.rules.select { |rule| rule.property == variable }
        expect(rules.map { |rule| [rule.value, rule.conditions] }).to eq(expected)
      end
    end
  end

  it "keeps other variables and other sources, including identical shared rules, through replacement and unload" do
    a = "/reloadable/a.rb"
    b = "/permanent/b.rb"
    registry.with_source(a) { styles.define_vars(name: "shared", accent: { default: "red", dark: "black" }, gap: 2) }
    registry.with_source(b) { styles.define_vars(name: "shared", accent: { default: "red", dark: "black" }) }
    vars = registry.with_source(a) { styles.define_vars(name: "shared", accent: "blue") }
    values = registry.rules.select { |rule| rule.property == vars.var_name(:accent) }.map(&:value)
    expect(values).to contain_exactly("red", "black", "blue")
    expect(registry.rules.map(&:value)).to include("2")

    allow(registry).to receive(:reloadable_roots).and_return(["/reloadable/"])
    registry.clear_reloadable
    expect(registry.rules.map(&:value)).to contain_exactly("red", "black")
  end

  it "rolls back removals and additions together and successfully retries" do
    original = styles.define_vars(name: "retry", accent: { default: "red", dark: "black" }, gap: 2)
    baseline = registry.to_css
    expect do
      styles.define_vars(name: "retry", accent: "blue", gap: { bogus: 3 })
    end.to raise_error(ArgumentError)
    expect(registry.to_css).to eq(baseline)

    styles.define_vars(name: "retry", accent: "blue", gap: 3)
    expect(registry.rules.select { |rule| rule.property == original.var_name(:accent) }.map(&:value)).to eq(["blue"])
    expect(registry.rules.map(&:value)).to contain_exactly("blue", "3")
  end

  it "preserves replacement order inside an outer transaction, including empty assignments" do
    registry.transaction do
      styles.define_vars(name: "ordered", accent: { default: "red", dark: "black" })
      styles.define_vars(name: "ordered", accent: {})
      styles.define_vars(name: "ordered", accent: { print: "blue" })
      expect(registry.size).to eq(0)
    end
    expect(registry.rules.map { |rule| [rule.value, rule.conditions] }).to eq([["blue", ["@media print"]]])
  end
end
