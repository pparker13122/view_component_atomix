# frozen_string_literal: true

require "rails_helper"

require "tmpdir"

RSpec.describe "css output" do
  let(:styles) { ViewComponent::Atomix }
  let!(:registry) { with_fresh_registry }

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
end
