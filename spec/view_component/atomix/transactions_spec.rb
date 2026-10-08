# frozen_string_literal: true

require "rails_helper"

RSpec.describe "transactions" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  it "rolls back partially compiled style and variable declarations" do
    expect { styles.create(root: { color: "red", padding: { bogus: 1 } }) }.to raise_error(ArgumentError)
    expect(registry.size).to eq(0)
    expect { styles.define_vars(name: "failed", accent: "blue", gap: { bogus: 2 }) }.to raise_error(ArgumentError)
    expect(registry.size).to eq(0)
  end

  it "rolls back all groups of a failed theme and retries it" do
    a = styles.define_vars(name: "a", accent: "red")
    b = styles.define_vars(name: "b", gap: 2)
    owner = Class.new { include ViewComponent::Atomix }
    allow(owner).to receive(:resolved_styles).and_return(styles::Sheet.new({}, accent: a, gap: b))
    ready = false
    owner.theme { { accent: "blue", gap: { (ready ? :default : :bogus) => 4 } } }
    baseline = registry.to_css
    expect { owner.theme }.to raise_error(ArgumentError)
    expect(registry.to_css).to eq(baseline)
    ready = true
    expect(owner.theme.classes.size).to eq(2)
  end

  it "retains successfully compiled dependencies when an outer block fails" do
    dependency = Class.new do
      include ViewComponent::Atomix
      styles root: { color: "red" }
    end
    owner = Class.new do
      include ViewComponent::Atomix
      styles do
        dependency.styles
        trait :root, padding: { bogus: 2 }
      end
    end
    expect { owner.styles }.to raise_error(ArgumentError)
    expect(registry.rules.map(&:value)).to eq(["red"])
    expect(registry.to_css).to include(dependency.styles.root.class_names)
  end

  it "does not retain dynamic styles from a failed compilation" do
    dynamics = styles::WeakCollection.new
    allow(styles).to receive(:dynamic_styles).and_return(dynamics)
    expect do
      styles.create(box: { dynamic: [:width], using: ->(value) { { width: value } } }, bad: { color: { bogus: "red" } })
    end.to raise_error(ArgumentError)
    expect(dynamics.to_a).to be_empty
    expect(registry.size).to eq(0)
    styles.compile_dynamic_styles!
    expect(registry.size).to eq(0)
  end

  it "keeps a successfully created constant when the consuming declaration fails" do
    registry = with_fresh_registry
    dependency = Module.new
    ready = false
    owner = Class.new do
      include ViewComponent::Atomix
      styles do
        unless dependency.const_defined?(:VARS)
          dependency.const_set(:VARS, ViewComponent::Atomix.define_vars(name: "dependency", accent: "red"))
        end
        trait :root, color: dependency::VARS.accent, padding: { (ready ? :default : :bogus) => 2 }
      end
    end
    expect { owner.styles }.to raise_error(ArgumentError)
    expect(registry.rules.map(&:selector)).to eq([":root"])
    ready = true
    root = owner.styles.root
    expect(registry.to_css).to include(root.class_names.split.first)
    expect(registry.to_css).to include(":root{#{dependency::VARS.var_name(:accent)}:red}")
  end

  it "rolls back and retries a failed theme spanning separate declarations" do
    stub_const("RetrySplitTheme", Class.new)
    RetrySplitTheme.class_eval do
      include ViewComponent::Atomix
      style_vars accent: "red"
      style_vars surface: "white"
    end
    ready = false
    RetrySplitTheme.theme { { accent: "blue", surface: { (ready ? :default : :bogus) => "black" } } }
    baseline = registry.to_css
    expect { RetrySplitTheme.theme }.to raise_error(ArgumentError)
    expect(registry.to_css).to eq(baseline)
    ready = true
    expect(RetrySplitTheme.theme.class_names.split.size).to eq(1)
    expect(registry.rules.count { |rule| rule.selector == ".#{RetrySplitTheme.theme.class_names}" }).to eq(2)
  end
end
