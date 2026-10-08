# frozen_string_literal: true

RSpec.describe ViewComponent::Atomix::DynamicProperties::SourceCache do
  subject(:cache) { described_class.new }

  it "reuses unchanged source and reparses a changed file" do
    Tempfile.create(["dynamic-properties", ".rb"]) do |file|
      file.write("-> { { max_height: 1 } }")
      file.flush
      first = cache.fetch(file.path)
      expect(cache.fetch(file.path)).to equal(first)

      modified = File.mtime(file.path) + 60
      File.write(file.path, "-> { { min_height: 1 } }")
      File.utime(modified, modified, file.path)
      updated = cache.fetch(file.path)
      expect(updated).not_to equal(first)
      expect(ViewComponent::Atomix::DynamicProperties.properties_from(updated.fetch(1).first, "Spec", :box))
        .to eq(["min-height"])
    end
  end

  it "retries an invalid source after it is corrected" do
    Tempfile.create(["dynamic-properties", ".rb"]) do |file|
      file.write("-> {")
      file.flush
      expect(cache.fetch(file.path)).to be_nil

      modified = File.mtime(file.path)
      File.write(file.path, "-> { { opacity: 1 } }")
      File.utime(modified, modified, file.path)
      expect(cache.fetch(file.path).keys).to eq([1])
    end
  end

  it "evicts older parsed files when the cache reaches its limit" do
    stub_const("#{described_class}::LIMIT", 1)
    Tempfile.create(["dynamic-first", ".rb"]) do |first|
      Tempfile.create(["dynamic-second", ".rb"]) do |second|
        [first, second].each do |file|
          file.write("-> { {} }")
          file.flush
        end
        original = cache.fetch(first.path)
        cache.fetch(second.path)
        expect(cache.fetch(first.path)).not_to equal(original)
      end
    end
  end
end
