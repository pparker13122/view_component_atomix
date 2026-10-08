# frozen_string_literal: true

RSpec.describe "dynamic literal key syntax" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

  [true, false].each do |inline|
    it "matches Ruby's runtime keys for supported literal forms (inline=#{inline})" do
      allow(styles.config).to receive(:inline?).and_return(inline)
      functions = [
        ->(v) { { width: v } },
        ->(v) { { :width => v } },
        ->(v) { { :'width' => v } },
        ->(v) { { :"width" => v } },
        ->(v) { { "width": v } },
        ->(v) { { 'width': v } },
        ->(v) { { %s(width) => v } },
        ->(v) { { %s[width] => v } },
        ->(v) { { :"\x77idth" => v } },
        ->(v) { { "\u0077idth": v } },
        ->(v) { { :'\x77idth' => v } },
        ->(v) { { :'--gap' => v } },
        ->(v) { { "minWidth": v } },
        ->(v) { { %q(width) => v } },
        ->(v) { { %Q(\x77idth) => v } },
        ->(v) { { "width" => v, :'min-height' => v, 'height' => v, "--gap": v } }
      ]
      functions.each_with_index do |fn, index|
        expected = fn.call(12).keys.map { |key| styles::Property.normalize_key(key) }
        expect(styles::DynamicProperties.extract(fn, name: "forms", set: :box)).to eq(expected)
        dynamic = styles::DynamicStyle.new(name: "form-#{index}", set: :box, fn: fn)
        dynamic.compile! unless inline
        rendered = dynamic.call(12)
        expect(rendered.classes.keys).to eq(expected)
        rendered.classes.zip(rendered.inline.keys).each do |(property, names), var|
          expect(registry.rules).to include(
            have_attributes(selector: ".#{names.first}", property: property, value: "var(#{var})")
          )
        end
      end
    end
  end

  it "rejects interpolated symbols and labels without evaluating keys or values" do
    executed = false
    functions = [
      ->(v) { { :"#{executed = true}" => v } },
      ->(v) { { "#{executed = true}": v } },
      ->(v) { { (executed = true) => v } }
    ]
    functions.each do |fn|
      expect { styles::DynamicProperties.extract(fn, name: "unsafe", set: :box) }
        .to raise_error(styles::DynamicProperties::Unsupported)
    end
    literal = ->(v) { { :'width' => (executed = true; v) } }
    expect(styles::DynamicProperties.extract(literal, name: "safe", set: :box)).to eq(["width"])
    expect(executed).to be(false)
  end
end
