# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "spec_helper"
require "rails"
# Core specs load the gems before Rails. Install their conditional integrations
# explicitly before booting the application.
require "view_component/engine"
require "view_component/atomix/railtie"
require_relative "dummy/config/environment"
require "rspec/rails"
require "view_component/test_helpers"
require "capybara/rspec"

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/view_component/atomix/}) do |metadata|
    metadata[:rails] = true
  end

  config.before(:each, :rails) do
    # Invalid declarations intentionally created by an example must not be
    # retried by a later example's eager load. Keep the application owners.
    includers = ViewComponent::Atomix::WeakCollection.new
    ViewComponent::Atomix.includers.each { |owner| includers << owner }
    allow(ViewComponent::Atomix).to receive(:includers).and_return(includers)
  end

  config.include ViewComponent::TestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
end
