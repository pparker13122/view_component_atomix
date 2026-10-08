# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::Property do
  describe ".normalize_key" do
    it "converts snake_case symbols to kebab-case" do
      expect(described_class.normalize_key(:border_radius)).to eq("border-radius")
    end

    it "converts camelCase strings to kebab-case" do
      expect(described_class.normalize_key("backgroundColor")).to eq("background-color")
    end

    it "leaves custom properties untouched" do
      expect(described_class.normalize_key("--myVar_x")).to eq("--myVar_x")
    end
  end

  describe ".normalize_value" do
    it "adds px to numbers" do
      expect(described_class.normalize_value("padding", 8)).to eq("8px")
      expect(described_class.normalize_value("padding", 1.5)).to eq("1.5px")
    end

    it "keeps zero unitless" do
      expect(described_class.normalize_value("margin", 0)).to eq("0")
    end

    it "keeps unitless properties unitless" do
      expect(described_class.normalize_value("line-height", 1.5)).to eq("1.5")
      expect(described_class.normalize_value("z-index", 10)).to eq("10")
      expect(described_class.normalize_value("font-weight", 600)).to eq("600")
    end

    it "normalizes arrays element-wise" do
      expect(described_class.normalize_value("width", [100, :fit_content, "50%"])).to eq(["100px", "fit-content", "50%"])
    end

    it "converts symbols to kebab-case values" do
      expect(described_class.normalize_value("display", :inline_block)).to eq("inline-block")
    end
  end

  describe ".priority" do
    it "orders shorthands below longhands" do
      expect(described_class.priority("padding")).to eq(1000)
      expect(described_class.priority("border-radius")).to eq(2000)
      expect(described_class.priority("padding-inline")).to eq(2000)
      expect(described_class.priority("margin-block-start")).to eq(3000)
      expect(described_class.priority("padding-top")).to eq(4000)
    end

    it "adds pseudo-class weight in LVHFA order" do
      link = described_class.priority("color", [":link"])
      visited = described_class.priority("color", [":visited"])
      hover = described_class.priority("color", [":hover"])
      focus = described_class.priority("color", [":focus"])
      active = described_class.priority("color", [":active"])
      expect(link).to be < visited
      expect(visited).to be < hover
      expect(hover).to be < focus
      expect(focus).to be < active
    end

    it "handles functional pseudo-classes and at-rules" do
      expect(described_class.priority("color", [":nth-child(2)"])).to eq(4060)
      expect(described_class.priority("color", ["@media (max-width: 1px)"])).to eq(4200)
      expect(described_class.priority("color", ["@supports (display: grid)"])).to eq(4030)
      expect(described_class.priority("color", ["::before"])).to eq(9000)
    end
  end

  describe ".validate_value!" do
    it "accepts values whose structure is self-contained" do
      [
        "red", "1px solid #000", "rgb(0 0 0 / 50%)", "calc((100% - 2px) / 3)", 'url("data:image/png;base64,AAAA")',
        "url(data:image/png;base64,AAAA)", '"a;b"', "'it\\'s'", "1 / 2", "red /* note */", "[row-start] 1fr", ""
      ].each do |value|
        expect(described_class.validate_value!("color", value)).to equal(value)
      end
    end

    it "rejects values that could end the declaration or swallow what follows" do
      [
        "red;background:blue", "red}body{display:none", "url(x", "calc(1px))", '"open', "'a\nb'", "red /* open",
        "trailing\\", "(]"
      ].each do |value|
        expect { described_class.validate_value!("color", value) }.to raise_error(ArgumentError, /Unsafe CSS value for color/)
      end
    end

    it "applies to normalized strings and symbols but not numbers" do
      expect { described_class.normalize_value("color", "red;x:y") }.to raise_error(ArgumentError, /Unsafe CSS value/)
      expect(described_class.normalize_value("width", 10)).to eq("10px")
      expect(described_class.normalize_value("display", :inline_block)).to eq("inline-block")
    end
  end
end
