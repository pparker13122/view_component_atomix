# frozen_string_literal: true

require "rails_helper"

require "tmpdir"
require "open3"

RSpec.describe "lifecycle" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  it "does not expose a reentrant partial sheet to another thread" do
    entered = Queue.new
    release = Queue.new
    owner = Class.new do
      include ViewComponent::Atomix
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

  it "refreshes cached descendants when a parent's accessor changes mixin selection" do
    shared = Module.new do
      include ViewComponent::Atomix
      styles_method :styles
      styles shared_trait: { color: "red" }
    end
    parent = Class.new { include shared }
    child = Class.new(parent)
    grandchild = Class.new(child)
    expect(grandchild.styles.names).to eq([:shared_trait])

    parent.styles_method :css
    expect(parent.css).to be_empty
    expect(child.css).to be_empty
    expect(grandchild.new.css).to be_empty

    parent.styles_method :styles
    expect(grandchild.styles.names).to eq([:shared_trait])
  end

  it "makes completed earlier blocks visible to later reentrant reads" do
    owner = Class.new do
      include ViewComponent::Atomix
      styles { trait :first, color: styles.primary }
      styles { trait :second, color: styles.first.classes.keys.first }
    end
    expect(owner.styles.names).to eq(%i[first second])
  end

  it "refreshes sheets merged from modules and companions" do
    shared = Module.new do
      include ViewComponent::Atomix
      styles root: { color: "red" }
    end
    owner = Class.new { include shared }
    expect(owner.styles.names).to eq([:root])
    shared.styles extra: { padding: 3 }
    expect(owner.styles.names).to eq(%i[root extra])

    stub_const("RefreshingComponentStyles", shared)
    stub_const("RefreshingComponent", Class.new { include ViewComponent::Atomix })
    expect(RefreshingComponent.styles.names).to eq(%i[root extra])
    shared.styles later: { margin: 4 }
    expect(RefreshingComponent.styles.names).to include(:later)
  end

  it "explicitly removes unloaded owners even while they remain strongly referenced" do
    owner = Class.new do
      include ViewComponent::Atomix
      styles { trait :root, color: { bogus: "red" } }
    end
    resolved = []
    parent = Class.new do
      include ViewComponent::Atomix
      styles do
        resolved << :parent
        trait :root, color: "red"
      end
    end
    child = Class.new(parent) do
      styles do
        resolved << :child
        trait :root, color: "blue"
      end
    end
    styles.unload!(owner, __FILE__)
    styles.unload!(child, __FILE__)
    expect(styles.includers).not_to include(owner)
    expect(styles.includers).to include(parent)
    expect { styles.eager_load! }.not_to raise_error
    expect(resolved).to eq([:parent])
  end

  it "resets declarations and caches together, allowing owners to be reused", :preserve_styles_configuration do
    owner = Class.new do
      include ViewComponent::Atomix
      styles root: { color: "red" }
      style_vars accent: "blue"
      theme accent: "green"
    end
    owner.styles
    owner.theme
    collection = styles::WeakCollection.new << owner
    dynamics = styles::WeakCollection.new
    allow(styles).to receive(:includers).and_return(collection)
    allow(styles).to receive(:dynamic_styles).and_return(dynamics)
    dynamic = styles.create(sized: ->(width) { { width: width } })[:sized]
    vars = styles.define_vars(name: "reset-vars", accent: "red")
    styles.vars = vars
    styles.config.class_prefix = "zz"
    expect(dynamics.to_a).to eq([dynamic])
    expect(styles.configured_vars).to equal(vars)
    styles.reset!
    expect(registry.size).to eq(0)
    expect(dynamics).not_to include(dynamic)
    expect(styles.configured_vars).to be_nil
    expect(styles.config.class_prefix).to eq("vc")
    expect(owner.styles).to be_empty
    expect(owner.theme).to be_empty
    owner.styles fresh: { padding: 5 }
    fresh = owner.styles.fresh
    expect(registry.to_css).to include(fresh.class_names)
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

  it "keeps tracked owners and dynamic styles from accumulating across real Rails reloads" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require File.expand_path("spec/dummy/config/environment")
      styles = ViewComponent::Atomix
      tracked = -> { { includers: styles.includers.count, dynamic_styles: styles.dynamic_styles.count } }
      Rails.application.reloader.reload!
      before = tracked.call
      abort "expected tracked owners and dynamic styles, got #{before}" if before.values.any?(&:zero?)
      5.times { Rails.application.reloader.reload! }
      after = tracked.call
      abort "tracked #{before} after one reload but #{after} after six" unless after == before
    SCRIPT
    output, status = Open3.capture2e({ "RAILS_ENV" => "development" }, "bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end

  it "refreshes cached descendant sheets and themes when a module is included" do
    vars = ViewComponent::Atomix.define_vars(name: "late-mixin", accent: "red")
    shared = Module.new do
      include ViewComponent::Atomix
      styles extra: { padding: 3 }
      theme vars, accent: "blue"
    end
    parent = Class.new { include ViewComponent::Atomix }
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
