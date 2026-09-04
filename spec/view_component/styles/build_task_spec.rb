# frozen_string_literal: true

require "rake"

RSpec.describe "view_component:styles:build" do
  let(:output_path) { Rails.root.join(ViewComponent::Styles.config.output_path) }

  before do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../../lib/view_component/styles/tasks/build.rake", __dir__)
  end

  after { FileUtils.rm_f(output_path) }

  it "runs before every other assets:precompile prerequisite" do
    Rake::Task.define_task("css:build")
    Rake::Task["assets:precompile"].enhance(["css:build"])
    prerequisites = Rake::Task["assets:precompile"].prerequisites
    expect(prerequisites.index("view_component:styles:build")).to be < prerequisites.index("css:build")
  end

  it "writes the registry css to the configured path" do
    expect { Rake::Task["view_component:styles:build"].invoke }.to output(/Wrote \d+ rules to/).to_stdout
    expect(output_path).to exist
    css = output_path.read
    expect(css).to eq("#{ViewComponent::Styles.registry.to_css}\n")
    expect(css).to include(ButtonComponent.styles.base.classes["padding"].join)
    expect(css).to include(CardStyles::CARD.title.classes["font-size"].join)
    expect(css).to include(BadgeStyles::BADGE.root.classes["font-size"].join)
  end

  it "compiles dynamic rules before the trait receives a runtime value" do
    with_fresh_registry
    allow(ViewComponent::Styles.config).to receive(:inline?).and_return(false)
    ViewComponent::Styles::DynamicStyle.new(
      name: "BuildSpec", set: :sized, fn: ->(width) { { width: width } }
    )

    expect { Rake::Task["view_component:styles:build"].invoke }.to output(/Wrote \d+ rules to/).to_stdout
    css = output_path.read

    # Model a separately booted production web process. It has the same
    # definition identity but does not participate in the asset build.
    runtime_dynamic = ViewComponent::Styles::DynamicStyle.new(
      name: "BuildSpec", set: :sized, fn: ->(width) { { width: width } }
    )
    size = ViewComponent::Styles.registry.size
    rendered = runtime_dynamic.call(123)
    klass = rendered.class_names
    variable = rendered.inline.keys.fetch(0)

    expect(css).to include(".#{klass}{width:var(#{variable})}")
    expect(rendered.inline.fetch(variable)).to eq("123px")
    expect(ViewComponent::Styles.registry.size).to eq(size)
  end
end
