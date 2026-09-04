# frozen_string_literal: true

require "tmpdir"
require "open3"

RSpec.describe "lifecycle" do
  let(:styles) { ViewComponent::Styles }
  let!(:registry) { with_fresh_registry }

  it "does not expose a reentrant partial sheet to another thread" do
    entered = Queue.new
    release = Queue.new
    owner = Class.new do
      include ViewComponent::Styles
      styles do
        styles
        entered << true
        release.pop
        trait :root, color: "red"
      end
    end
    compiling = Thread.new { owner.styles }
    entered.pop
    reader = Thread.new { owner.styles.root }
    expect(reader.join(0.05)).to be_nil
    release << true
    expect(reader.value).to eq(compiling.value.root)
  ensure
    release << true if release
    [compiling, reader].compact.each(&:join)
  end

  it "makes completed earlier blocks visible to later reentrant reads" do
    owner = Class.new do
      include ViewComponent::Styles
      styles { trait :first, color: styles.primary }
      styles { trait :second, color: styles.first.classes.keys.first }
    end
    expect(owner.styles.names).to eq(%i[first second])
  end

  it "refreshes sheets merged from modules and companions" do
    shared = Module.new do
      include ViewComponent::Styles
      styles root: { color: "red" }
    end
    owner = Class.new { include shared }
    expect(owner.styles.names).to eq([:root])
    shared.styles extra: { padding: 3 }
    expect(owner.styles.names).to eq(%i[root extra])

    stub_const("RefreshingComponentStyles", shared)
    stub_const("RefreshingComponent", Class.new { include ViewComponent::Styles })
    expect(RefreshingComponent.styles.names).to eq(%i[root extra])
    shared.styles later: { margin: 4 }
    expect(RefreshingComponent.styles.names).to include(:later)
  end

  it "explicitly removes unloaded owners even while they remain strongly referenced" do
    owner = Class.new do
      include ViewComponent::Styles
      styles { trait :root, color: { bogus: "red" } }
    end
    styles.unload!(owner, __FILE__)
    expect(styles.includers).not_to include(owner)
    expect { styles.eager_load! }.not_to raise_error
  end

  it "resets declarations and caches together, allowing owners to be reused" do
    owner = Class.new do
      include ViewComponent::Styles
      styles root: { color: "red" }
      style_vars accent: "blue"
      theme accent: "green"
    end
    owner.styles
    owner.theme
    collection = styles::WeakCollection.new << owner
    allow(styles).to receive(:includers).and_return(collection)
    previous_config = styles.config.dup
    previous_vars = styles.instance_variable_get(:@vars)
    allow(styles).to receive(:dynamic_styles).and_return(styles::WeakCollection.new)
    styles.reset!
    expect(registry.size).to eq(0)
    expect(owner.styles).to be_empty
    expect(owner.theme).to be_empty
    owner.styles fresh: { padding: 5 }
    fresh = owner.styles.fresh
    expect(registry.to_css).to include(fresh.class_names)
  ensure
    previous_config&.instance_variables&.each do |ivar|
      styles.config.instance_variable_set(ivar, previous_config.instance_variable_get(ivar))
    end
    styles.instance_variable_set(:@vars, previous_vars)
  end

  it "recovers a real Rails reload after a broken declaration is corrected" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require "tmpdir"
      require "fileutils"
      Dir.mktmpdir do |dir|
        FileUtils.cp_r("spec/dummy", File.join(dir, "dummy"))
        require File.join(dir, "dummy/config/environment")
        path = Rails.root.join("app/components/lazy_component.rb")
        original = File.read(path)
        File.write(path, original.sub('display: "grid"', 'display: { bogus: "grid" }'))
        begin
          Rails.application.reloader.reload!
          abort "expected bad reload to fail"
        rescue ArgumentError
        end
        File.write(path, original)
        Rails.application.reloader.reload!
        abort "missing restored style" unless LazyComponent.styles.root.classes.key?("display")
      end
    SCRIPT
    output, status = Open3.capture2e({ "RAILS_ENV" => "development" }, "bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end

  it "refreshes cached descendant sheets and themes when a module is included" do
    vars = ViewComponent::Styles.define_vars(name: "late-mixin", accent: "red")
    shared = Module.new do
      include ViewComponent::Styles
      styles extra: { padding: 3 }
      theme vars, accent: "blue"
    end
    parent = Class.new { include ViewComponent::Styles }
    child = Class.new(parent)
    grandchild = Class.new(child)
    expect(grandchild.styles).to be_empty
    expect(grandchild.theme).to be_empty
    parent.include(shared)
    expect(grandchild.styles.names).to eq([:extra])
    expect(grandchild.theme).to eq(shared.theme)
    expect(grandchild.theme).not_to be_empty
  end
end
