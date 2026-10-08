# frozen_string_literal: true

require "logger" # Rails 7.0 relies on Logger being loaded before Active Support.
require "view_component_atomix"
require "rspec/core"
require "rspec/expectations"
require "rspec/mocks"

module RegistryIsolation
  def with_fresh_registry
    registry = ViewComponent::Atomix::Registry.new
    allow(ViewComponent::Atomix).to receive(:registry).and_return(registry)
    registry
  end
end

module ConfigurationIsolation
  SETTINGS = %i[class_prefix pseudo_map breakpoints vars eager_load_paths autoload_roots use_layers inline output_path styles_method].freeze

  def with_preserved_styles_configuration
    styles = ViewComponent::Atomix
    configuration = styles.config
    settings = SETTINGS.to_h { |name| [name, configuration.public_send(name)] }
    assigned_vars = styles.instance_variable_get(:@vars)
    yield
  ensure
    settings.each { |name, value| configuration.public_send("#{name}=", value) }
    styles.vars = assigned_vars
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.define_derived_metadata(file_path: %r{/spec/core/}) do |metadata|
    metadata[:core] = true
  end

  config.before(:each, :core) do
    styles = ViewComponent::Atomix
    allow(styles).to receive(:config).and_return(styles::Configuration.new)
    allow(styles).to receive(:includers).and_return(styles::WeakCollection.new)
    allow(styles).to receive(:dynamic_styles).and_return(styles::WeakCollection.new)
    with_fresh_registry
  end

  config.around(:each, :preserve_styles_configuration) do |example|
    with_preserved_styles_configuration { example.run }
  end

  config.include ConfigurationIsolation
  config.include RegistryIsolation
end
