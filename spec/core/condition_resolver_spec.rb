# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::ConditionResolver do
  it "keeps classification and resolution on the same configuration snapshot" do
    breakpoints = { small: +"(max-width: 600px)" }
    pseudos = { before: +"::before", hover: +":hover" }
    resolver = described_class.new(breakpoints: breakpoints, pseudo_map: pseudos)

    breakpoints[:small].replace("(max-width: 900px)")
    pseudos[:before].replace(":focus")
    pseudos[:active] = ":active"

    expect(resolver.breakpoint?(:small)).to be(true)
    expect(resolver.condition?(:small)).to be(true)
    expect(resolver.resolve(:small)).to eq("@media (max-width: 600px)")
    expect(resolver.pseudo_element?(:before)).to be(true)
    expect(resolver.resolve(:before)).to eq("::before")
    expect(resolver.condition?(:active)).to be(false)
    expect { resolver.resolve(:active) }.to raise_error(ArgumentError, /Unknown style condition/)
  end

  it "recognizes raw conditions while rejecting plain property names" do
    resolver = described_class.new(breakpoints: {}, pseudo_map: {})
    [":hover", "::before", "@supports (display: grid)"].each do |condition|
      expect(resolver.condition?(condition)).to be(true)
      expect(resolver.resolve(condition)).to eq(condition)
    end
    expect(resolver.pseudo_element?("::before")).to be(true)
    expect(resolver.condition?("color")).to be(false)
    expect { resolver.resolve("color") }.to raise_error(ArgumentError, /must start with/)
  end
end
