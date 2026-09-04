# frozen_string_literal: true

RSpec.describe "companion style modules", type: :component do
  it "merges a module named after the component into its styles" do
    expect(ToastComponent.styles.names).to eq(%i[root tone cta])
    expect(ToastComponent.styles.root).to equal(ToastComponentStyles.styles.root)
    expect(ToastComponent.new.styles).to equal(ToastComponent.styles)
    expect(ToastComponent).not_to respond_to(:toast_component_styles)
  end

  it "lets the component reference companion traits and vars" do
    expect(ToastComponent.styles.cta.classes.keys).to include("display", "font-weight")
    expect(ToastComponent.styles.var_names).to include(:gap)
    expect(ToastComponent.styles.gap).to eq(ToastComponentStyles.styles.gap)
  end

  it "merges the companion theme into theme" do
    expect(ToastComponent.theme.classes.keys).to eq(["theme:#{Brand::VARS.id}"])
    expect(ToastComponent.theme).to eq(ToastComponentStyles.theme)
  end

  it "renders companion styles" do
    render_inline(ToastComponent.new) { "hi" }
    div = page.find("div")
    classes = div[:class].split
    expect(classes).to include(*ToastComponent.theme.class_names.split)
    expect(classes).to include(*ToastComponent.styles.root.class_names.split)
    expect(classes).to include(*ToastComponent.styles.tone.class_names.split)
  end

  it "lets the component's own traits win over the companion" do
    stub_const("BannerComponentStyles", Module.new do
      include ViewComponent::Styles
      styles root: { padding: 4 }, label: { color: "red" }
    end)
    stub_const("BannerComponent", Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      styles root: { margin: 1 }
    end)

    expect(BannerComponent.styles.names).to eq(%i[root label])
    expect(BannerComponent.styles.root.classes.keys).to eq(["margin"])
  end

  it "looks up the companion in the component's namespace" do
    stub_const("Admin::NoteComponentStyles", Module.new do
      include ViewComponent::Styles
      styles root: { padding: 4 }
    end)
    stub_const("Admin::NoteComponent", Class.new(ViewComponent::Base) { include ViewComponent::Styles })

    expect(Admin::NoteComponent.styles.names).to eq(%i[root])
  end

  it "looks up a companion per subclass and inherits the parent's" do
    stub_const("ChildToastComponentStyles", Module.new do
      include ViewComponent::Styles
      styles large: { font_size: 20 }
    end)
    child = stub_const("ChildToastComponent", Class.new(ToastComponent))
    plain = stub_const("PlainToastComponent", Class.new(ToastComponent))

    expect(child.styles.names).to eq(%i[root tone cta large])
    expect(plain.styles.names).to eq(%i[root tone cta])
  end

  it "ignores constants that are not style modules" do
    stub_const("AlertComponentStyles", Class.new)
    stub_const("AlertComponent", Class.new(ViewComponent::Base) { include ViewComponent::Styles })
    stub_const("NoticeComponentStyles", Module.new { ROOT = 1 })
    stub_const("NoticeComponent", Class.new(ViewComponent::Base) { include ViewComponent::Styles })

    expect(AlertComponent.styles).to be_empty
    expect(NoticeComponent.styles).to be_empty
  end

  it "works with a renamed styles method" do
    stub_const("ChipComponentStyles", Module.new do
      include ViewComponent::Styles
      styles root: { padding: 4 }
    end)
    stub_const("ChipComponent", Class.new(ViewComponent::Base) do
      include ViewComponent::Styles
      styles_method :css
      css label: { color: "red" }
    end)

    expect(ChipComponent.css.names).to eq(%i[root label])
  end

  it "compiles companion styles on eager load" do
    css = ViewComponent::Styles.eager_load!.to_css
    expect(css).to include(".#{ToastComponent.styles.root.classes["padding"].join}{padding:12px}")
  end
end
