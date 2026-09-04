# frozen_string_literal: true

RSpec.describe ViewComponent::Styles::WeakCollection do
  it "deduplicates by identity while retaining distinct equal objects" do
    collection = described_class.new
    first = +"same"
    second = +"same"
    collection << first << first << second
    expect(collection.map(&:object_id)).to eq([first.object_id, second.object_id])
  end

  it "drops collected references during enumeration and insertion" do
    collection = described_class.new
    3.times { collection << Object.new }
    GC.start
    expect(collection.to_a).to be_empty
    survivor = Object.new
    collection << survivor
    expect(collection.to_a).to eq([survivor])
  end

  it "clears the collection and permits reuse" do
    collection = described_class.new
    object = Object.new
    collection << object
    expect(collection.clear).to equal(collection)
    expect(collection.each.to_a).to be_empty
    collection << object
    expect(collection.to_a).to eq([object])
  end
end
