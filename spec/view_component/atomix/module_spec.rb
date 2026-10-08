# frozen_string_literal: true

require "rails_helper"

RSpec.describe ViewComponent::Atomix do
  before { with_fresh_registry }

  describe ".create" do
    it "accepts a braceless hash, an explicit hash, or a block" do
      a = described_class.create(base: { color: "red" })
      b = described_class.create({ base: { color: "red" } })
      c = described_class.create { { base: { color: "red" } } }
      expect([a, b, c].map { |s| s.base.class_names }.uniq.length).to eq(1)
    end

    it "requires definitions" do
      expect { described_class.create }.to raise_error(ArgumentError, /requires a Hash or a block/)
    end

    it "accepts an explicit dynamic property list as an escape hatch" do
      sheet = described_class.create(
        box: { dynamic: %i[width height], using: ->(x) { x ? { width: x } : { height: 0 } } }
      )

      expect(sheet.box(2).classes.keys).to eq(["width"])
    end
  end

  describe ".props and .sx" do
    let(:sheet) { described_class.create(a: { color: "red" }, b: { padding: 2 }, w: ->(w) { { width: w } }) }

    it "merges and skips nil and false" do
      attrs = described_class.props(sheet.a, nil, false, sheet.b, sheet.w(3))
      expect(attrs[:class].split.length).to eq(3)
      expect(attrs[:style]).to match(/\A--vc\w+:3px\z/)
    end

    it "renders html-safe attributes" do
      html = described_class.sx(sheet.a, sheet.w(3))
      expect(html).to be_html_safe
      expect(html).to match(/\Aclass="vc\w+ vc\w+" style="--vc\w+:3px"\z/)
    end

    it "escapes inline values" do
      html = described_class.sx(sheet.w('"<script>"'))
      expect(html).to include("&quot;&lt;script&gt;&quot;")
    end

    it "returns an empty string for nothing" do
      expect(described_class.sx(nil)).to eq("")
    end

    it "rejects uncalled dynamic styles and foreign objects" do
      expect { described_class.sx(sheet[:w]) }.to raise_error(ArgumentError, /must be called/)
      expect { described_class.sx("class") }.to raise_error(ArgumentError, /Expected/)
    end
  end

  describe ".write_css" do
    let(:path) { Rails.root.join("tmp/write_css_spec.css") }

    after { FileUtils.rm_f(path) }

    it "writes only when the registry changed" do
      described_class.create(a: { color: "red" })
      expect(described_class.write_css("tmp/write_css_spec.css")).to eq(path)
      first_mtime = path.mtime

      FileUtils.touch(path, mtime: first_mtime - 60)
      described_class.write_css("tmp/write_css_spec.css")
      expect(path.mtime).to eq(first_mtime - 60)

      described_class.create(a: { color: "blue" })
      described_class.write_css("tmp/write_css_spec.css")
      expect(path.mtime).to be > first_mtime - 60
      expect(path.read).to eq("#{described_class.registry.to_css}\n")
    end
  end

  describe ".vars" do
    it "resolves the configured callable" do
      expect(described_class.vars).to equal(Brand::VARS)
    end

    it "prefers explicitly assigned vars and raises when nothing is configured", :preserve_styles_configuration do
      vars = described_class.define_vars(x: 1)
      described_class.vars = vars
      expect(described_class.vars).to equal(vars)
    end

    it "raises when nothing is configured" do
      allow(described_class.config).to receive(:vars).and_return(nil)
      expect(described_class.configured_vars).to be_nil
      expect { described_class.vars }.to raise_error(described_class::VarsNotConfigured, /config.view_component.atomix.vars/)
    end
  end
end
