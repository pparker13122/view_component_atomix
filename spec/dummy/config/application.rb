# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie"
require "view_component"
require "view_component_atomix"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "dummy"
    config.hosts.clear
    config.logger = Logger.new(File::NULL)
    config.active_support.deprecation = :stderr
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = false
    config.assets.debug = false
    config.assets.quiet = true

    config.view_component.atomix.breakpoints = { md: "@media (max-width: 768px)" }
    config.view_component.atomix.vars = -> { Brand::VARS }
  end
end
