# frozen_string_literal: true

require "rails_helper"

require "open3"

RSpec.describe "Rails integration", type: :request do
  let(:styles) { ViewComponent::Atomix }

  it "exposes config under config.view_component.atomix" do
    expect(Rails.application.config.view_component.atomix).to equal(styles.config)
    expect(styles.config).to be_inline
    expect(styles.config.breakpoints).to eq({ md: "@media (max-width: 768px)" })
  end

  it "does not inline styles in a production process" do
    project = File.expand_path("../../..", __dir__)
    script = <<~'SCRIPT'
      require "logger"
      require File.expand_path("spec/dummy/config/environment")
      abort "expected production to link the built stylesheet" if ViewComponent::Atomix.config.inline?
    SCRIPT
    output, status = Open3.capture2e({ "RAILS_ENV" => "production" }, "bundle", "exec", "ruby", "-e", script, chdir: project)
    expect(status.success?).to be(true), output
  end

  it "renders the inline stylesheet with rules for components and plain styles" do
    get "/", params: { width: 90 }
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    css = doc.at_css("style[data-view-component-atomix]").text
    expect(css).to start_with(":root{")

    button_classes = doc.css("button").flat_map { |b| b["class"].split }
    card_classes = doc.at_css("#card")["class"].split
    body_classes = doc.at_css("body")["class"].split
    (button_classes + card_classes + body_classes).uniq.each do |klass|
      expect(css).to include(".#{klass}"), "expected css to include .#{klass}"
    end

    expect(doc.at_css("button")["style"]).to match(/\A--vc\w+:90px\z/)
    expect(css).to include(":root{#{Brand::VARS.var_name(:primary)}:#0055ff}")
    expect(css).to include("@media (max-width: 768px){")
  end

  it "renders a stylesheet link tag when not inlining" do
    path = Rails.root.join(styles.config.output_path)
    File.write(path, styles.registry.to_css)
    allow(styles.config).to receive(:inline?).and_return(false)

    get "/"
    expect(response.body).to include('href="/assets/view_component_atomix')
    expect(response.body).not_to include("<style")
  ensure
    FileUtils.rm_f(path)
  end

  it "preserves nested logical paths in the stylesheet link tag", :preserve_styles_configuration do
    styles.config.output_path = "app/assets/builds/admin/components.css"
    path = Rails.root.join(styles.config.output_path)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, styles.registry.to_css)
    allow(styles.config).to receive(:inline?).and_return(false)

    get "/"
    expect(response.body).to include('href="/assets/admin/components')
  ensure
    FileUtils.rm_rf(path.dirname)
  end

  it "provides sx in plain views" do
    get "/"
    classes = Nokogiri::HTML(response.body).at_css("#card")["class"].split
    expect(classes).to include(*CardStyles::CARD.root.class_names.split)
    expect(classes).to include(*CardStyles::CARD.title.class_names.split)
  end
end
