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
    expect(Rake::Task["assets:precompile"].prerequisites).to eq(%w[view_component:styles:build css:build])
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
end
