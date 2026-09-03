# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

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

  config.include ViewComponent::TestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
  config.include RegistryIsolation
end
