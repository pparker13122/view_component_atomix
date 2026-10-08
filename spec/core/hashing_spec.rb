# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::Hashing do
  it "is deterministic and prefixed" do
    ViewComponent::Atomix.config.class_prefix = "zz"
    a = described_class.class_name("color", "red", [":hover"])
    b = described_class.class_name("color", "red", [":hover"])
    expect(a).to eq(b)
    expect(a).to match(/\Azz[a-z0-9]{12}\z/)
  end

  it "preserves part and fallback-value boundaries" do
    expect(described_class.digest("a|b", "c")).not_to eq(described_class.digest("a", "b|c"))
    expect(described_class.digest(["a,b", "c"])).not_to eq(described_class.digest(["a", "b,c"]))
    expect(described_class.digest(["a", "b"])).not_to eq(described_class.digest("a", "b"))
    expect(described_class.digest("a", "sb")).not_to eq(described_class.digest("as", "b"))
    expect(described_class.digest(["a"], "b")).not_to eq(described_class.digest(["a", "b"]))
  end

  it "differs by property, value and condition" do
    base = described_class.class_name("color", "red")
    expect(described_class.class_name("color", "blue")).not_to eq(base)
    expect(described_class.class_name("background", "red")).not_to eq(base)
    expect(described_class.class_name("color", "red", [":hover"])).not_to eq(base)
  end

  it "builds var names with the prefix" do
    ViewComponent::Atomix.config.class_prefix = "zz"
    expect(described_class.var_name("a", "b")).to match(/\A--zz[a-z0-9]{12}\z/)
  end
end
