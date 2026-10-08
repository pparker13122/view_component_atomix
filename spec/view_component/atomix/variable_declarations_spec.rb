# frozen_string_literal: true

require "rails_helper"

RSpec.describe "variable declarations" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  it "preserves variable order across deferred and immediate declarations" do
    owner = Class.new do
      include ViewComponent::Atomix
      style_vars { { accent: "red" } }
      style_vars accent: "blue"
    end
    variable = owner.styles.vars_for(:accent).var_name(:accent)
    expect(registry.rules.select { |rule| rule.property == variable }.map(&:value)).to eq(["blue"])
  end

  it "allows a variable to return to a previous value" do
    owner = Class.new { include ViewComponent::Atomix }
    %w[red blue red].each { |color| owner.style_vars accent: color }
    variable = owner.styles.vars_for(:accent).var_name(:accent)
    expect(registry.rules.select { |rule| rule.property == variable }.map(&:value)).to eq(["red"])
  end
end
