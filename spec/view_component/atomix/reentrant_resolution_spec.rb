# frozen_string_literal: true

require "rails_helper"

RSpec.describe "reentrant resolution caches and limits" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  it "does not cache incomplete inheritance through multiple consumers" do
    parent = Class.new { include ViewComponent::Atomix }
    child = Class.new(parent)
    grandchild = Class.new(child)
    calls = 0
    child.styles { grandchild.styles; nil }
    parent.styles do
      calls += 1
      child.styles
      trait :root, color: "blue"
    end

    result = parent.styles
    expect(parent.styles).to equal(result)
    expect(child.styles.names).to eq([:root])
    expect(grandchild.styles.names).to eq([:root])
    expect(calls).to eq(1)
  end

  it "does not cache an inherited theme before its parent finishes" do
    vars = styles.define_vars(name: "reentrant-theme", accent: "red")
    parent = Class.new { include ViewComponent::Atomix }
    child = Class.new(parent)
    parent.theme(vars) { child.theme; { accent: "blue" } }

    result = parent.theme
    expect(parent.theme).to equal(result)
    expect(child.theme).to eq(result)
    expect(registry.to_css).to include(":blue}")
  end

  %i[mixin companion].each do |dependency_kind|
    %i[styles theme].each do |kind|
      it "does not cache incomplete #{kind} from a #{dependency_kind}" do
        dependency = Module.new { include ViewComponent::Atomix }
        if dependency_kind == :mixin
          owner = Class.new { include dependency }
        else
          stub_const("ReentrantCompanionStyles", dependency)
          stub_const("ReentrantCompanion", Class.new { include ViewComponent::Atomix })
          owner = ReentrantCompanion
        end

        if kind == :styles
          dependency.styles { owner.styles; trait :root, color: "blue" }
          dependency.styles
          expect(owner.styles.names).to eq([:root])
        else
          vars = styles.define_vars(name: "dependency-theme", accent: "red")
          dependency.theme(vars) { owner.theme; { accent: "blue" } }
          result = dependency.theme
          expect(owner.theme).to eq(result)
          expect(result).not_to be_empty
        end
      end
    end
  end

  [false, true].each do |indirect|
    [false, true].each do |explicit|
      it "retries a failed reentrant theme (indirect=#{indirect}, explicit=#{explicit})" do
        owner = Class.new { include ViewComponent::Atomix }
        vars = styles.define_vars(name: "retry-theme", accent: "red")
        owner.style_vars(name: "retry-theme", accent: "red") unless explicit
        owner.styles { owner.theme; trait :root, color: "black" } if indirect
        ready = false
        calls = 0
        owner.theme(explicit ? vars : nil) do
          calls += 1
          indirect ? owner.styles : owner.theme
          raise "retry" unless ready
          { accent: "green" }
        end
        expect { owner.theme }.to raise_error("retry")
        ready = true
        result = owner.theme
        expect(result).not_to be_empty
        expect(owner.theme).to equal(result)
        expect(calls).to eq(2)
        expect(registry.to_css).to include(":green}")
      end
    end
  end

  it "rebuilds consumer inheritance after its parent fails and retries" do
    parent = Class.new { include ViewComponent::Atomix }
    child = Class.new(parent)
    ready = false
    parent.styles do
      child.styles
      raise "retry" unless ready
      trait :root, color: "blue"
    end
    expect { parent.styles }.to raise_error("retry")
    ready = true
    expect(parent.styles.names).to eq([:root])
    expect(child.styles.names).to eq([:root])
  end

  [false, true].each do |alternate_owners|
    it "shares recursive work limits and permits retry (alternate owners=#{alternate_owners})" do
      stub_const("ViewComponent::Atomix::DeclarationQueue::MAX_DRAIN_PASSES", 3)
      owner = Class.new { include ViewComponent::Atomix }
      other = alternate_owners ? Class.new { include ViewComponent::Atomix } : owner
      generate = true
      calls = 0
      enqueue = nil
      enqueue = lambda do |target, next_owner|
        target.style_vars(name: "bounded") do
          calls += 1
          raise "test safety stop" if calls > 10
          if generate
            enqueue.call(next_owner, target)
            next_owner.styles
          end
          { accent: "blue" }
        end
      end
      enqueue.call(owner, other)
      expect { owner.styles }.to raise_error(ArgumentError, /keep adding work/)
      expect(calls).to eq(3)
      generate = false
      expect(owner.styles.var_names).to eq([:accent])
      expect(other.styles.var_names).to eq([:accent])
      expect(registry.to_css).to include(":blue}")
    end
  end

  it "bounds recursive depth with the default work limit and cleans up for retry" do
    owner = Class.new { include ViewComponent::Atomix }
    generate = true
    calls = 0
    declaration = nil
    declaration = proc do
      calls += 1
      raise "test safety stop" if calls > 100
      if generate
        owner.style_vars(name: "depth", &declaration)
        owner.styles
      end
      { accent: "blue" }
    end
    owner.style_vars(name: "depth", &declaration)
    expect { owner.styles }.to raise_error(ArgumentError, /nesting limit/)
    expect(calls).to be < 100
    generate = false
    expect(owner.styles.var_names).to eq([:accent])
    unrelated = Class.new { include ViewComponent::Atomix }
    unrelated.styles(root: { color: "green" })
    expect(unrelated.styles.names).to eq([:root])
  end

  it "retains completed nested variables and their CSS when an outer declaration retries" do
    owner = Class.new { include ViewComponent::Atomix }
    ready = false
    queued = false
    calls = []
    owner.style_vars(name: "finite") do
      calls << :outer
      unless queued
        queued = true
        owner.style_vars(name: "finite") { calls << :inner; { accent: "blue" } }
      end
      expect(owner.styles.var_names).to include(:accent)
      raise "retry" unless ready
      { gap: 4 }
    end
    expect { owner.styles }.to raise_error("retry")
    expect(registry.to_css).to include(":blue}")
    ready = true
    expect(owner.styles.var_names).to contain_exactly(:accent, :gap)
    expect(calls).to eq(%i[outer inner outer])
  end

  it "does not cache dependent variables during a failed immediate declaration's drain" do
    parent = Class.new { include ViewComponent::Atomix }
    child = Class.new(parent)
    ready = false
    parent.style_vars(name: "immediate-dependency") do
      child.styles
      raise "retry" unless ready
      { accent: "blue" }
    end
    expect { parent.style_vars(name: "immediate-dependency", gap: 4) }.to raise_error("retry")
    ready = true
    expect(parent.styles.var_names).to eq([:accent])
    expect(child.styles.var_names).to eq([:accent])
  end
end
