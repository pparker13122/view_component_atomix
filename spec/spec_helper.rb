# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "logger" # Rails 7.0 relies on Logger being loaded before Active Support.
require_relative "dummy/config/environment"
require "rspec/rails"
require "view_component/test_helpers"
require "capybara/rspec"

module RegistryIsolation
  def with_fresh_registry
    registry = ViewComponent::Styles::Registry.new
    allow(ViewComponent::Styles).to receive(:registry).and_return(registry)
    registry
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before do
    # Invalid declarations intentionally created by an example must not be
    # retried by a later example's eager load.
    includers = ViewComponent::Styles::WeakCollection.new
    ViewComponent::Styles.includers.each { |owner| includers << owner }
    allow(ViewComponent::Styles).to receive(:includers).and_return(includers)
  end

  config.include ViewComponent::TestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
  config.include RegistryIsolation
end
