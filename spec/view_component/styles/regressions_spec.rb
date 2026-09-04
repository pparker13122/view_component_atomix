# frozen_string_literal: true

require "tmpdir"
require "open3"

RSpec.describe "style lifecycle regressions" do
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

  it "preserves variable order across deferred and immediate declarations" do
    owner = Class.new do
      include ViewComponent::Styles
      style_vars { { accent: "red" } }
      style_vars accent: "blue"
    end
    variable = owner.styles.vars_for(:accent).var_name(:accent)
    expect(registry.rules.select { |rule| rule.property == variable }.map(&:value)).to eq(["blue"])
  end

  it "allows a variable to return to a previous value" do
    owner = Class.new { include ViewComponent::Styles }
    %w[red blue red].each { |color| owner.style_vars accent: color }
    variable = owner.styles.vars_for(:accent).var_name(:accent)
    expect(registry.rules.select { |rule| rule.property == variable }.map(&:value)).to eq(["red"])
  end

  it "refreshes inherited themes after a parent declaration" do
    vars = styles.define_vars(name: "theme-cache", accent: "red")
    parent = Class.new { include ViewComponent::Styles }
    parent.theme(vars, accent: "blue")
    child = Class.new(parent)
    old = child.theme
    parent.theme(vars, accent: "green")
    expect(child.theme).to eq(parent.theme)
    expect(child.theme).not_to eq(old)
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

  it "writes each destination and repairs externally truncated output" do
    styles.create(root: { color: "red" })
    Dir.mktmpdir do |dir|
      first = File.join(dir, "first.css")
      second = File.join(dir, "second.css")
      File.write(second, "stale")
      styles.write_css(first)
      styles.write_css(second)
      expect(File.read(second)).to eq(File.read(first))
      File.write(first, "truncated")
      styles.write_css(first)
      expect(File.read(first)).to eq("#{registry.to_css}\n")
    end
  end

  it "preserves the previous output on failure and permits a retry" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "styles.css")
      File.write(path, "previous")
      File.chmod(0o640, path)
      allow(File).to receive(:rename).and_raise(IOError, "interrupted")
      expect { styles.write_css(path) }.to raise_error(IOError, "interrupted")
      expect(File.read(path)).to eq("previous")
      expect(Dir.children(dir)).to eq(["styles.css"])
      allow(File).to receive(:rename).and_call_original
      styles.write_css(path)
      expect(File.read(path)).to eq("#{registry.to_css}\n")
      expect(File.stat(path).mode & 0o777).to eq(0o640)
    end
  end

  it "rolls back partially compiled style and variable declarations" do
    expect { styles.create(root: { color: "red", padding: { bogus: 1 } }) }.to raise_error(ArgumentError)
    expect(registry.size).to eq(0)
    expect { styles.define_vars(name: "failed", accent: "blue", gap: { bogus: 2 }) }.to raise_error(ArgumentError)
    expect(registry.size).to eq(0)
  end

  it "rolls back all groups of a failed theme and retries it" do
    a = styles.define_vars(name: "a", accent: "red")
    b = styles.define_vars(name: "b", gap: 2)
    owner = Class.new { include ViewComponent::Styles }
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
      include ViewComponent::Styles
      styles root: { color: "red" }
    end
    owner = Class.new do
      include ViewComponent::Styles
      styles do
        dependency.styles
        trait :root, padding: { bogus: 2 }
      end
    end
    expect { owner.styles }.to raise_error(ArgumentError)
    expect(registry.rules.map(&:value)).to eq(["red"])
    expect(registry.to_css).to include(dependency.styles.root.class_names)
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
end

RSpec.describe "transaction and theme contracts" do
  let(:styles) { ViewComponent::Styles }
  let!(:registry) { with_fresh_registry }

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

  it "replaces an inherited theme for the same variable set while retaining other sets" do
    palette = styles.define_vars(name: "palette", accent: "red", surface: "white")
    spacing = styles.define_vars(name: "spacing", gap: 2)
    parent = Class.new { include ViewComponent::Styles }
    parent.theme(palette, accent: "blue", surface: "black")
    parent.theme(spacing, gap: 4)
    child = Class.new(parent)
    child.theme(palette, accent: "green")
    expected = styles.merge(styles.create_theme(palette, accent: "green"), styles.create_theme(spacing, gap: 4))
    expect(child.theme).to eq(expected)
    expect(child.theme.class_names.split).not_to include(parent.theme.classes.fetch("theme:palette").first)
  end
end

RSpec.describe "declaration dependency retries" do
  it "keeps a successfully created constant when the consuming declaration fails" do
    registry = with_fresh_registry
    dependency = Module.new
    ready = false
    owner = Class.new do
      include ViewComponent::Styles
      styles do
        unless dependency.const_defined?(:VARS)
          dependency.const_set(:VARS, ViewComponent::Styles.define_vars(name: "dependency", accent: "red"))
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
end
