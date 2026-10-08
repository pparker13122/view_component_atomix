# frozen_string_literal: true

require "rails_helper"

RSpec.describe "work added during owner resolution" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  it "finishes successive style and variable batches on the first read without rerunning successful declarations" do
    owner = Class.new { include ViewComponent::Atomix }
    calls = []
    owner.style_vars(name: "queued") do
      calls << :vars
      owner.style_vars(name: "queued") { { accent: "red" } }
      { gap: 2 }
    end
    owner.styles do
      calls << :first
      owner.styles do
        calls << :second
        owner.style_vars(name: "queued") { { surface: "white" } }
        owner.styles(extra: { padding: 3 })
        trait :other, color: styles.accent
      end
      trait :root, margin: 1
    end
    sheet = owner.styles
    expect(sheet.names).to eq(%i[root other extra])
    expect(sheet.var_names).to contain_exactly(:gap, :accent, :surface)
    expect(owner.styles).to equal(sheet)
    expect(calls).to eq(%i[vars first second])
  end

  %i[parent mixin companion].each do |dependency_kind|
    it "includes work added by a #{dependency_kind} while assembling the owner's context" do
      dependency = dependency_kind == :parent ? Class.new : Module.new
      dependency.include(ViewComponent::Atomix)
      if dependency_kind == :parent
        owner = Class.new(dependency)
      elsif dependency_kind == :mixin
        owner = Class.new { include dependency }
      else
        stub_const("QueuedCompanionStyles", dependency)
        stub_const("QueuedCompanion", Class.new { include ViewComponent::Atomix })
        owner = QueuedCompanion
      end
      dependency.styles do
        owner.styles(extra: { padding: 3 })
        trait :root, color: "red"
      end
      expect(owner.styles.names).to eq(%i[root extra])
      expect(owner.styles.names).to eq(%i[root extra])
    end
  end

  it "processes theme work added by both its own block and its parent" do
    vars = styles.define_vars(name: "theme-work", accent: "red")
    parent = Class.new { include ViewComponent::Atomix }
    child = Class.new(parent)
    calls = 0
    child.theme(vars) do
      calls += 1
      child.theme(vars, accent: "green")
      { accent: "blue" }
    end
    parent.theme(vars) do
      child.theme(vars, accent: "purple")
      { accent: "black" }
    end
    selected = child.theme
    expect(selected).to eq(styles.create_theme(vars, accent: "purple"))
    expect(child.theme).to equal(selected)
    expect(calls).to eq(1)
  end

  it "rejects declarations that endlessly generate more work and permits recovery" do
    stub_const("ViewComponent::Atomix::DeclarationQueue::MAX_DRAIN_PASSES", 3)
    owner = Class.new { include ViewComponent::Atomix }
    generate = true
    declaration = proc do
      owner.styles(&declaration) if generate
      trait :root, color: "red"
    end
    owner.styles(&declaration)
    expect { owner.styles }.to raise_error(ArgumentError, /keep adding work/)
    generate = false
    expect(owner.styles.names).to eq([:root])
  end

  it "serializes declaration writes with a concurrent reader" do
    owner = Class.new { include ViewComponent::Atomix }
    entered = Queue.new
    release = Queue.new
    owner.styles do
      entered << true
      release.pop
      trait :root, color: "red"
    end
    reader = Thread.new { owner.styles }
    entered.pop
    writer = Thread.new { owner.styles(extra: { padding: 3 }) }
    expect(writer.join(0.05)).to be_nil
    release << true
    [reader, writer].each(&:value)
    expect(owner.styles.names).to eq(%i[root extra])
  ensure
    release << true if release
    [reader, writer].compact.each(&:join)
  end
end
