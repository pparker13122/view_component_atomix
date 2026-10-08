# frozen_string_literal: true

require "rails_helper"

RSpec.describe ViewComponent::Atomix, type: :component do
  it "retains failed and subsequent declarations until compilation succeeds" do
    ready = false
    successful_calls = 0
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      styles do
        successful_calls += 1
        trait :first, padding: 2
      end
      styles do
        styles # A reentrant read must not leave a cached partial sheet after failure.
        raise "not ready" unless ready
        trait :second, color: "red"
      end
      styles { trait :third, margin: 4 }
    end
    2.times { expect { klass.styles }.to raise_error("not ready") }
    ready = true
    expect(klass.styles.names).to eq(%i[first second third])
    expect(successful_calls).to eq(1)
  end

  it "serializes the first resolution of a component's styles" do
    started = Queue.new
    release = Queue.new
    results = Queue.new
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      styles do
        started << true
        release.pop
        { root: { color: "red" } }
      end
    end

    compiling = Thread.new { klass.styles }
    started.pop
    concurrent = Thread.new do
      results << klass.styles.root
    rescue StandardError => error
      results << error
    end
    deadline = Time.now + 5
    sleep 0.001 until concurrent.stop? || Time.now > deadline
    blocked = concurrent.status == "sleep"
    release << true
    [compiling, concurrent].each(&:join)

    expect(blocked).to be(true)
    expect(results.pop).to be_a(ViewComponent::Atomix::Style)
  end

  it "renders merged classes and dynamic inline vars" do
    render_inline(ButtonComponent.new(variant: :primary, width: 120)) { "Save" }

    button = page.find("button")
    classes = button[:class].split
    variable, value = button[:style].split(":", 2)
    dynamic_class = ViewComponent::Atomix::Hashing.class_name("width", "var(#{variable})")

    expect(classes).to include(ButtonComponent.styles.base.classes["padding"].first)
    expect(classes).to include(ButtonComponent.styles.primary.classes["background"].first)
    expect(classes).not_to include(*ButtonComponent.styles.base.classes["background"])
    expect(classes).to include(dynamic_class)
    expect(value).to eq("120px")
    expect(button.text).to eq("Save")
  end

  it "lets the variant replace the base background including its hover class" do
    base_only = ButtonComponent.styles.base.classes["background"]
    merged = ViewComponent::Atomix.merge(ButtonComponent.styles.base, ButtonComponent.styles.primary)
    expect(base_only.length).to eq(2)
    expect(merged.classes["background"]).to eq(ButtonComponent.styles.primary.classes["background"])
  end

  it "omits the style attribute when the dynamic value is nil" do
    render_inline(ButtonComponent.new(variant: :secondary)) { "x" }
    expect(page.find("button")[:style]).to be_nil
  end

  it "accepts styles passed from a parent, which win" do
    extra = ViewComponent::Atomix.create(cta: { color: "hotpink" })
    render_inline(ButtonComponent.new(styles: extra.cta)) { "x" }
    expect(page.find("button")[:class]).to include(extra.cta.class_names)
    expect(page.find("button")[:class]).not_to include(ButtonComponent.styles.primary.classes["color"].join)
  end

  it "reads configured vars through styles inside class bodies" do
    expect(ButtonComponent.styles.primary.classes["background"]).to eq(
      ViewComponent::Atomix.create(x: { background: Brand::VARS.primary }).x.classes["background"]
    )
  end

  it "extends parent sheets in subclasses without mutating the parent" do
    expect(PrimaryButtonComponent.styles.names).to eq(%i[base primary secondary sized large])
    expect(PrimaryButtonComponent.styles.primary).to equal(ButtonComponent.styles.primary)
    expect(PrimaryButtonComponent.styles.base).not_to equal(ButtonComponent.styles.base)
    expect(ButtonComponent.styles.names).not_to include(:large)

    render_inline(PrimaryButtonComponent.new) { "Big" }
    expect(page.find("button")[:class]).to include(PrimaryButtonComponent.styles.large.class_names)
  end

  it "compiles block definitions lazily and once" do
    evaluations = 0
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      styles do
        evaluations += 1
        { root: { display: "grid", gap: 12 } }
      end
    end
    expect(evaluations).to eq(0)
    expect(klass.styles.root.classes.keys).to eq(%w[display gap])
    expect(klass.styles).to equal(klass.styles)
    expect(evaluations).to eq(1)

    expect(LazyComponent.styles.root.classes.keys).to eq(%w[display gap color])
    expect(LazyComponent.styles).to equal(LazyComponent.styles)
    render_inline(LazyComponent.new)
    expect(page.find("section")[:class]).to eq(LazyComponent.styles.root.class_names)
  end

  it "merges repeated styles calls" do
    klass = Class.new(ViewComponent::Base) do
      include ViewComponent::Atomix
      styles a: { color: "red" }
      styles b: { color: "blue" }
      styles a: { padding: 1 }
    end
    expect(klass.styles.names).to eq(%i[a b])
    expect(klass.styles.a.classes.keys).to eq(["padding"])
  end

  it "returns an empty sheet for components without styles" do
    klass = Class.new(ViewComponent::Base) { include ViewComponent::Atomix }
    expect(klass.styles).to be_empty
    expect(klass.new.styles).to be_empty
  end

  it "exposes sx_attrs on instances" do
    component = ButtonComponent.new
    expect(component.sx_attrs(ButtonComponent.styles.base)).to eq(ButtonComponent.styles.base.to_attrs)
  end

  describe "renaming the styles method" do
    it "exposes the sheet under the new name and removes the old one" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix
        styles_method :css
        css base: { color: "red" }
        css { { extra: { padding: 2 } } }
      end

      expect(klass.styles_method).to eq(:css)
      expect(klass.css.names).to eq(%i[base extra])
      expect(klass.new.css).to equal(klass.css)
      expect(klass).not_to respond_to(:styles)
      expect(klass.new).not_to respond_to(:styles)
    end

    it "is inherited and still extends the parent sheet" do
      parent = stub_const("CssParentComponent", Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix
        styles_method :css
        css base: { color: "red" }
      end)
      child = Class.new(parent) { css large: { padding: 8 } }

      expect(child.styles_method).to eq(:css)
      expect(child.css.names).to eq(%i[base large])
      expect(parent.css.names).to eq(%i[base])
    end

    it "can be renamed again in a subclass" do
      parent = stub_const("SheetParentComponent", Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix
        styles base: { color: "red" }
      end)
      child = Class.new(parent) do
        styles_method :sheet
        sheet large: { padding: 8 }
      end

      expect(child.sheet.names).to eq(%i[base large])
      expect(child).not_to respond_to(:styles)
      expect(parent).to respond_to(:styles)
    end

    it "defaults to the configured name for new includers", :preserve_styles_configuration do
      ViewComponent::Atomix.config.styles_method = :css
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix
        css base: { color: "red" }
      end

      expect(klass.css.base.classes.keys).to eq(["color"])
      expect(klass).not_to respond_to(:styles)
      expect(ButtonComponent).to respond_to(:styles)
    end

    it "still compiles renamed sheets on eager load" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix
        styles_method :css
        css { { base: { color: "orange" } } }
      end
      registry = ViewComponent::Atomix.eager_load!
      expect(registry.to_css).to include(klass.css.base.class_names)
    end
  end

  describe "style modules" do
    it "exposes a module's sheet under its underscored name at class and instance level" do
      expect(PillStyles.styles.names).to eq(%i[pill])
      expect(PillComponent.styles.names).to eq(%i[tone])
      expect(PillComponent.pill_styles.names).to eq(%i[pill])
      expect(PillComponent.pill_styles.pill).to equal(PillStyles.styles.pill)
      expect(PillComponent.new.pill_styles).to equal(PillComponent.pill_styles)
      expect(PillComponent.new.styles).to equal(PillComponent.styles)
    end

    it "renders module styles alongside local ones" do
      render_inline(PillComponent.new) { "new" }
      span = page.find("span")
      expected = ViewComponent::Atomix.props(PillComponent.pill_styles.pill, PillComponent.styles.tone)
      expect(span[:class]).to eq(expected[:class])
      expect(span.text).to eq("new")
    end

    it "derives the accessor from the module name" do
      stub_const("Admin::ProfileCardStyles", Module.new do
        include ViewComponent::Atomix
        styles root: { padding: 4 }
      end)
      klass = Class.new(ViewComponent::Base) { include Admin::ProfileCardStyles }
      expect(klass.admin_profile_card_styles.root.classes.keys).to eq(["padding"])
      expect(klass.new.admin_profile_card_styles).to equal(klass.admin_profile_card_styles)
    end

    it "merges an anonymous module into the component's styles" do
      anonymous = Module.new do
        include ViewComponent::Atomix
        styles root: { padding: 4 }
      end
      klass = Class.new(ViewComponent::Base) do
        include anonymous
        styles tone: { color: "red" }
      end
      expect(klass.styles.names).to eq(%i[root tone])
      expect(klass.styles.root).to equal(anonymous.styles.root)
    end

    it "exposes a module's explicit styles_method under that name" do
      stub_const("TagStyles", Module.new do
        include ViewComponent::Atomix
        styles_method :css
        css tag: { padding: 4 }
      end)
      klass = Class.new(ViewComponent::Base) do
        include TagStyles
        styles base: { margin: 1 }
      end
      expect(klass.css.names).to eq(%i[tag])
      expect(klass.styles.names).to eq(%i[base])
      expect(klass).not_to respond_to(:tag_styles)
      expect(klass.new.css).to equal(TagStyles.css)
    end

    it "merges when the module and the component declare the same styles_method" do
      stub_const("TagStyles", Module.new do
        include ViewComponent::Atomix
        styles_method :css
        css tag: { padding: 4 }, base: { color: "red" }
      end)
      klass = Class.new(ViewComponent::Base) do
        include TagStyles
        styles_method :css
        css base: { margin: 1 }
      end
      expect(klass.css.names).to eq(%i[tag base])
      expect(klass.css.tag).to equal(TagStyles.css.tag)
      expect(klass.css.base.classes.keys).to eq(["margin"])
      expect(klass.new.css).to equal(klass.css)
    end

    it "does not treat the configured default as an explicit override", :preserve_styles_configuration do
      ViewComponent::Atomix.config.styles_method = :css
      stub_const("TagStyles", Module.new do
        include ViewComponent::Atomix
        css tag: { padding: 4 }
      end)
      klass = Class.new(ViewComponent::Base) do
        include TagStyles
        css base: { margin: 1 }
      end
      expect(klass.css.names).to eq(%i[base])
      expect(klass.tag_styles.names).to eq(%i[tag])
    end

    it "works when the component already includes ViewComponent::Atomix" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Atomix
        styles base: { margin: 1 }
        include PillStyles
      end
      expect(klass.styles.names).to eq(%i[base])
      expect(klass.pill_styles.names).to eq(%i[pill])
    end

    it "is inherited by subclasses and tracked for eager loading" do
      child = Class.new(PillComponent)
      expect(child.styles.names).to eq(%i[tone])
      expect(child.pill_styles.names).to eq(%i[pill])
      expect(ViewComponent::Atomix.includers).to include(PillStyles, PillComponent)

      with_fresh_registry
      stub_const("EagerChipStyles", Module.new do
        include ViewComponent::Atomix
        styles chip: { letter_spacing: 3 }
      end)
      expect(ViewComponent::Atomix.includers).to include(EagerChipStyles)
      expect(ViewComponent::Atomix.eager_load!.to_css).to match(/^\.vc\w+\{letter-spacing:3px\}$/)
    end
  end
end
