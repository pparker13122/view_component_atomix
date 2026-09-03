# frozen_string_literal: true

RSpec.describe "traits" do
  let!(:registry) { with_fresh_registry }

  def create(**defs)
    ViewComponent::Styles.create(defs, name: "spec")
  end

  describe "enumerated traits" do
    let(:sheet) do
      create(size: { default: :regular, sm: { font_size: 14 }, regular: { font_size: 16 }, lg: { font_size: 20 } })
    end

    it "compiles to an EnumeratedStyle with one style per member" do
      expect(sheet[:size]).to be_a(ViewComponent::Styles::EnumeratedStyle)
      expect(sheet[:size].member_names).to eq(%i[sm regular lg])
      expect(sheet.size(:lg)).to be_a(ViewComponent::Styles::Style)
      expect(registry.rules.map(&:to_css)).to include(a_string_matching(/font-size:20px/))
    end

    it "returns the default for nil or no argument" do
      expect(sheet.size).to equal(sheet.size(:regular))
      expect(sheet.size(nil)).to equal(sheet.size(:regular))
      expect(sheet.fetch(:size, "sm")).to equal(sheet.size(:sm))
    end

    it "returns an empty style for nil when there is no default" do
      sheet = create(tone: { primary: { color: "red" }, secondary: { color: "blue" } })
      expect(sheet.tone(nil)).to be_empty
      expect(sheet.tone).to be_empty
    end

    it "raises for unknown members" do
      expect { sheet.size(:xl) }.to raise_error(KeyError, /Unknown member :xl for trait :size.*Available: \[:sm, :regular, :lg\]/)
    end

    it "raises when the default is not a member" do
      expect { create(size: { default: :xl, sm: { font_size: 14 } }) }
        .to raise_error(ArgumentError, /Default :xl is not a member of trait :size/)
    end

    it "resolves to the default when merged directly" do
      expect(ViewComponent::Styles.merge(sheet[:size])).to eq(sheet.size(:regular))
    end

    it "treats a hash of properties with conditions as a plain style, not members" do
      sheet = create(root: { color: { default: "red", hover: "blue" }, padding: 4 })
      expect(sheet.root).to be_a(ViewComponent::Styles::Style)
    end

    it "treats pseudo-element blocks as a plain style" do
      sheet = create(icon: { before: { content: '""' } })
      expect(sheet.icon).to be_a(ViewComponent::Styles::Style)
      expect(sheet.icon.classes.keys).to eq(["::beforecontent"])
    end

    it "allows any member name that is not a configured breakpoint or pseudo-class" do
      sheet = create(size: { sm: { font_size: 14 }, small: { font_size: 12 }, sm_up: { font_size: 18 } })
      expect(sheet[:size].member_names).to eq(%i[sm small sm_up])
      expect { create(root: { hover: { color: "red" } }) }.to raise_error(ArgumentError, /nested under a property/)
    end

    it "raises when a member is named after a configured breakpoint" do
      expect { create(size: { sm: { font_size: 14 }, md: { font_size: 16 } }) }
        .to raise_error(ArgumentError, /:md in style set :size is a configured breakpoint/)
    end

    it "raises when members are mixed with properties" do
      expect { create(size: { sm: { font_size: 14 }, padding: 4 }) }
        .to raise_error(ArgumentError, /mixes enumerated members \[:sm\] with \[:padding\]/)
    end
  end

  describe "combinations" do
    let(:sheet) do
      create(
        button: { padding: 8, color: "black" },
        size: { default: :regular, sm: { font_size: 14 }, regular: { font_size: 16 }, lg: { font_size: 20 } },
        cta: { button: true, size: :lg, font_weight: 700, color: "white" }
      )
    end

    it "merges referenced traits with own properties winning" do
      expect(sheet.cta).to eq(
        ViewComponent::Styles.merge(sheet.button, sheet.size(:lg), create(x_: { font_weight: 700, color: "white" }).x_)
      )
      expect(sheet.cta.classes.keys).to eq(%w[padding color font-size font-weight])
      expect(sheet.cta.classes["color"]).not_to eq(sheet.button.classes["color"])
    end

    it "uses the default member when an enumerated trait is referenced with true" do
      sheet = create(size: { default: :sm, sm: { font_size: 14 } }, cta: { size: true })
      expect(sheet.cta).to eq(sheet.size(:sm))
    end

    it "raises when an enumerated trait without a default is referenced with true" do
      expect { create(size: { sm: { font_size: 14 } }, cta: { size: true }) }
        .to raise_error(ArgumentError, /is enumerated; pass a member such as size: :sm/)
    end

    it "raises when a plain trait is referenced with a member" do
      expect { create(button: { padding: 8 }, cta: { button: :big }) }
        .to raise_error(ArgumentError, /Trait :button in :cta is not enumerated/)
    end

    it "raises when referencing a dynamic style" do
      expect { create(sized: ->(w) { { width: w } }, cta: { sized: 10 }) }
        .to raise_error(ArgumentError, /cannot reference the dynamic style :sized/)
    end

    it "only resolves references declared earlier" do
      sheet = create(cta: { button: { padding: 8 } }, button: { padding: 8 })
      expect(sheet[:cta]).to be_a(ViewComponent::Styles::EnumeratedStyle)
    end
  end

  it "accepts the trait DSL in create blocks" do
    sheet = ViewComponent::Styles.create do
      breakpoints tablet: "(max-width: 900px)"
      trait :root, padding: { default: 16, tablet: 8 }
      trait :size, sm: { font_size: 14 }, lg: { font_size: 20 }
      trait :hero, :root, size: :lg
    end
    expect(sheet.names).to eq(%i[root size hero])
    expect(sheet.hero.classes.keys).to eq(%w[padding font-size])
    expect(registry.rules.map(&:to_css)).to include(a_string_matching(/max-width: 900px/))
    expect { ViewComponent::Styles.create { styles } }.to raise_error(NameError)
  end

  it "rejects set names that are CSS properties" do
    expect { create(width: { padding: 4 }) }.to raise_error(ArgumentError, /:width is named after a CSS property/)
    expect { create(font_size: { padding: 4 }) }.to raise_error(ArgumentError, /:font_size is named/)
  end

  describe "breakpoints in a styles block" do
    it "scopes breakpoints to the component and its subclasses" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        def self.name = "ScopedBreakpointComponent"
        styles do
          breakpoints tablet: "(max-width: 900px)"
          trait :root, color: { default: "red", tablet: "blue", md: "green" }
        end
      end
      sub = Class.new(klass) do
        styles do
          trait :extra, padding: { default: 4, tablet: 8 }
        end
      end
      other = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        styles do
          trait :root, color: { default: "red", tablet: "blue" }
        end
      end

      expect(klass.styles.root.classes["color"].length).to eq(3)
      expect(sub.styles.extra.classes["padding"].length).to eq(2)
      expect(registry.rules.map(&:to_css)).to include(a_string_matching(/\A@media \(max-width: 900px\)\{\.vc\w+\{color:blue\}\}\z/))
      expect { other.styles }.to raise_error(ArgumentError, /Unknown style condition :tablet/)
    end

    it "overrides a configured breakpoint for one component" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        styles do
          breakpoints md: "(max-width: 1000px)"
          trait :root, color: { md: "blue" }
        end
      end
      klass.styles
      expect(registry.rules.map(&:to_css)).to include(a_string_matching(/max-width: 1000px/))
      expect(ViewComponent::Styles.config.breakpoints[:md]).to eq("@media (max-width: 768px)")
    end

    it "makes a scoped breakpoint name unavailable as a member" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        styles do
          breakpoints small: "(max-width: 600px)"
          trait :size, small: { font_size: 12 }, large: { font_size: 20 }
        end
      end
      expect { klass.styles }.to raise_error(ArgumentError, /:small in style set :size is a configured breakpoint/)
    end

    it "rejects non-string queries and pseudo-class names" do
      expect do
        Class.new(ViewComponent::Base) do
          include ViewComponent::Styles
          styles { breakpoints hover: "(max-width: 600px)" }
        end.styles
      end.to raise_error(ArgumentError, /collides with the pseudo-class/)
      expect do
        Class.new(ViewComponent::Base) do
          include ViewComponent::Styles
          styles { breakpoints sm: 600 }
        end.styles
      end.to raise_error(ArgumentError, /must be a String/)
    end
  end

  describe "props" do
    let(:sheet) { create(root: { padding: 4 }, sized: ->(w) { { width: w } }) }

    it "returns splat-able attrs that render as an html-safe attribute string" do
      attrs = sheet.props(sheet.root, sheet.sized(10))
      expect(attrs).to be_a(ViewComponent::Styles::Attrs)
      expect(attrs.keys).to eq(%i[class style])
      expect(attrs.to_s).to match(/\Aclass="vc\w+ vc\w+" style="--vc\w+:10px"\z/)
      expect(attrs.to_s).to be_html_safe
      expect(ViewComponent::Styles.sx(sheet.root, sheet.sized(10))).to eq(attrs.to_s)
    end

    it "escapes attribute values" do
      style = ViewComponent::Styles::Style.new({ "color" => ['a"b'] })
      expect(sheet.props(style).to_s).to eq('class="a&quot;b"')
    end

    it "returns empty attrs for nothing" do
      expect(sheet.props).to be_empty
      expect(sheet.props.to_s).to eq("")
    end

    it "renders inside a component template" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        def self.name = "PropsComponent"
        styles do
          trait :root, padding: 4
        end
        erb_template '<div <%= styles.props(styles.root) %>>x</div>'
      end
      html = ViewComponent::TestHelpers.instance_method(:render_inline).bind(Object.new.extend(ViewComponent::TestHelpers)).call(klass.new).to_html
      expect(html).to match(/<div class="vc\w+">x<\/div>/)
    end
  end

  describe "block DSL in components" do
    let(:component) do
      Class.new(ViewComponent::Base) do
        include ViewComponent::Styles

        def self.name = "TraitComponent"

        styles button: { padding: 8 }

        styles do
          trait :size, default: :regular, sm: { font_size: 14 }, regular: { font_size: 16 }, lg: { font_size: 20 }
          trait :tone,
                primary: { background: styles.primary, color: "#fff" },
                secondary: { background: "transparent", color: styles.primary }
          trait :disabled, { opacity: 0.5 }
          trait :cta, :button, size: :lg, tone: :primary, font_weight: 700
          trait :quiet, button: true, tone: :secondary, disabled: true
          trait :sized, ->(w) { { width: w } }
        end
      end
    end

    before { ViewComponent::Styles.vars = ViewComponent::Styles.define_vars(name: "spec", primary: "#0055ff") }
    after { ViewComponent::Styles.vars = nil }

    it "declares plain, enumerated, combination and dynamic traits" do
      sheet = component.styles
      expect(sheet.names).to eq(%i[button size tone disabled cta quiet sized])
      expect(sheet.size(:sm)).to be_a(ViewComponent::Styles::Style)
      expect(sheet.disabled.classes.keys).to eq(["opacity"])
      expect(sheet[:sized]).to be_a(ViewComponent::Styles::DynamicStyle)
    end

    it "resolves references to traits from earlier styles calls" do
      sheet = component.styles
      expect(sheet.cta).to eq(ViewComponent::Styles.merge(sheet.button, sheet.size(:lg), sheet.tone(:primary), create(f: { font_weight: 700 }).f))
      expect(sheet.quiet).to eq(ViewComponent::Styles.merge(sheet.button, sheet.tone(:secondary), sheet.disabled))
    end

    it "resolves configured vars through styles inside the block" do
      expect(component.styles.tone(:secondary).classes["color"]).to eq(
        create(c: { color: ViewComponent::Styles.vars.primary }).c.classes["color"]
      )
    end

    it "still accepts a returned hash" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        styles do
          { root: { padding: 4 } }
        end
      end
      expect(klass.styles.names).to eq([:root])
    end

    it "rejects a block that declares traits and returns a hash" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        styles do
          trait :root, padding: 4
          { other: { padding: 4 } }
        end
      end
      expect { klass.styles }.to raise_error(ArgumentError, /either declare traits or return a Hash/)
    end

    it "rejects duplicate trait names within a block" do
      klass = Class.new(ViewComponent::Base) do
        include ViewComponent::Styles
        styles do
          trait :root, padding: 4
          trait :root, padding: 8
        end
      end
      expect { klass.styles }.to raise_error(ArgumentError, /:root is already declared/)
    end

    it "lets subclasses reference inherited traits" do
      sub = Class.new(component) do
        styles do
          trait :hero, :cta, padding: 24
        end
      end
      expect(sub.styles.hero.classes["padding"]).not_to eq(component.styles.button.classes["padding"])
      expect(sub.styles.hero.classes["font-size"]).to eq(component.styles.size(:lg).classes["font-size"])
    end
  end
end
