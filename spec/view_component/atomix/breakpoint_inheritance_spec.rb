# frozen_string_literal: true

require "rails_helper"

RSpec.describe "breakpoint inheritance after parent updates" do
  let!(:registry) { with_fresh_registry }

  def conditions_for(style)
    selectors = style.class_names.split.map { |name| ".#{name}" }
    registry.rules.select { |rule| selectors.include?(rule.selector) }.map(&:conditions)
  end

  [false, true].each do |resolve_parent_first|
    [false, true].each do |override|
      it "uses current inherited queries while preserving local overrides (parent resolved=#{resolve_parent_first}, override=#{override})" do
        parent = Class.new { include ViewComponent::Atomix }
        parent.styles { breakpoints tablet: "(max-width: 900px)" }
        parent.styles
        child = Class.new(parent)
        child.styles { breakpoints phone: "(max-width: 400px)" }
        child.styles { breakpoints tablet: "(max-width: 700px)" } if override
        child.styles(root: { color: { tablet: "red" } })
        original = child.styles.root
        grandchild = Class.new(child)
        grandchild.styles

        parent.styles { breakpoints tablet: "(max-width: 1200px)" }
        parent.styles if resolve_parent_first
        child.styles(updated: { color: { tablet: "blue" }, padding: { phone: 4 } })
        grandchild.styles(extra: { margin: { tablet: 8 } })

        expected = "@media (max-width: #{override ? 700 : 1200}px)"
        expect(conditions_for(child.styles.updated)).to contain_exactly(
          [expected], ["@media (max-width: 400px)"]
        )
        expect(conditions_for(grandchild.styles.extra)).to eq([[expected]])
        expect(child.styles.root).to equal(original)
      end
    end
  end

  it "rolls back failed local overrides before retrying against updated inheritance" do
    parent = Class.new { include ViewComponent::Atomix }
    parent.styles { breakpoints tablet: "(max-width: 900px)" }
    parent.styles
    child = Class.new(parent)
    child.styles { breakpoints phone: "(max-width: 400px)" }
    child.styles
    ready = false
    child.styles do
      breakpoints tablet: "(max-width: 700px)" unless ready
      trait :root, color: { (ready ? :tablet : :bogus) => "red" }
    end
    baseline = registry.to_css
    expect { child.styles }.to raise_error(ArgumentError, /Unknown style condition/)
    expect(registry.to_css).to eq(baseline)
    parent.styles { breakpoints tablet: "(max-width: 1200px)" }
    ready = true
    expect(conditions_for(child.styles.root)).to eq([["@media (max-width: 1200px)"]])
  end
end
