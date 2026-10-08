# frozen_string_literal: true

require "rails_helper"

require "rake"
require "open3"

RSpec.describe "view_component:atomix:build" do
  let(:output_path) { Rails.root.join(ViewComponent::Atomix.config.output_path) }

  around do |example|
    previous_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = previous_application
  end

  before do
    Rake::Task.define_task(:environment)
    Rake::Task.define_task("css:build")
    Rake::Task.define_task("assets:precompile" => "css:build")
    load File.expand_path("../../../lib/view_component/atomix/tasks/build.rake", __dir__)
  end

  after { FileUtils.rm_f(output_path) }

  it "runs before every other assets:precompile prerequisite" do
    Rake::Task.define_task("javascript:build")
    Rake::Task["assets:precompile"].enhance(["javascript:build"])
    expect(Rake::Task["assets:precompile"].prerequisites)
      .to eq(%w[view_component:atomix:build css:build javascript:build])
  end

  it "writes the registry css to the configured path" do
    expect { Rake::Task["view_component:atomix:build"].invoke }.to output(/Wrote \d+ rules to/).to_stdout
    expect(output_path).to exist
    css = output_path.read
    expect(css).to eq("#{ViewComponent::Atomix.registry.to_css}\n")
    expect(css).to include(ButtonComponent.styles.base.classes["padding"].join)
    expect(css).to include(CardStyles::CARD.title.classes["font-size"].join)
    expect(css).to include(BadgeStyles::BADGE.root.classes["font-size"].join)
  end

  it "builds every style through the application's own task in a production process" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require "tmpdir"
      require "fileutils"
      require "rake"
      Dir.mktmpdir do |dir|
        FileUtils.cp_r("spec/dummy", File.join(dir, "dummy"))
        FileUtils.mkdir_p(File.join(dir, "dummy/app/presenters"))
        File.write(File.join(dir, "dummy/app/presenters/presenter_styles.rb"),
                   "PresenterStyles = ViewComponent::Atomix.create(root: { outline_width: 7 })\n")
        load File.join(dir, "dummy/Rakefile")
        Rake::Task["view_component:atomix:build"].invoke
        css = Rails.root.join(ViewComponent::Atomix.config.output_path).read
        sized = ButtonComponent.styles.sized(90)
        expected = {
          "a component" => ".#{ButtonComponent.styles.base.classes["padding"].join}{padding:8px 16px}",
          "a lazily declared component" => ".#{LazyComponent.styles.root.classes["display"].join}{display:grid}",
          "an app/styles module" => ".#{CardStyles::CARD.root.classes["padding"].join}{padding:24px}",
          "a dynamic trait" => ".#{sized.class_names}{width:var(#{sized.inline.keys.first})}",
          "a style outside the configured paths" =>
            ".#{PresenterStyles.root.classes["outline-width"].join}{outline-width:7px}"
        }
        missing = expected.reject { |_, rule| css.include?(rule) }.keys
        abort "built css is missing #{missing.join(", ")}:\n#{css}" unless missing.empty?
      end
    SCRIPT
    output, status = Open3.capture2e({ "RAILS_ENV" => "production" }, "bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end

  it "compiles dynamic rules before the trait receives a runtime value" do
    with_fresh_registry
    allow(ViewComponent::Atomix.config).to receive(:inline?).and_return(false)
    sheet = ViewComponent::Atomix.create(name: "BuildSpec", sized: ->(width) { { width: width } })

    expect { Rake::Task["view_component:atomix:build"].invoke }.to output(/Wrote \d+ rules to/).to_stdout
    css = output_path.read
    rendered = sheet.sized(123)
    expect(css).to include(".#{rendered.class_names}{width:var(#{rendered.inline.keys.first})}")

    # Model a separately booted production web process. It has the same
    # definition identity but does not participate in the asset build.
    runtime_dynamic = ViewComponent::Atomix::DynamicStyle.new(
      name: "BuildSpec", set: :sized, fn: ->(width) { { width: width } }
    )
    size = ViewComponent::Atomix.registry.size
    rendered = runtime_dynamic.call(123)
    klass = rendered.class_names
    variable = rendered.inline.keys.fetch(0)

    expect(css).to include(".#{klass}{width:var(#{variable})}")
    expect(rendered.inline.fetch(variable)).to eq("123px")
    expect(ViewComponent::Atomix.registry.size).to eq(size)
  end
end
