# frozen_string_literal: true

require "rails/railtie"

module ViewComponent
  module Atomix
    class Railtie < Rails::Railtie
      config.before_configuration do |app|
        app.config.view_component.atomix = ViewComponent::Atomix.config
        ViewComponent::Atomix.config.inline = !Rails.env.production?
      end

      initializer "view_component.atomix.autoload_roots", before: :set_load_path do |app|
        ViewComponent::Atomix.config.autoload_roots.each do |relative|
          app.config.paths.add relative.to_s, eager_load: true
          dir = app.root.join(relative.to_s).to_s
          next unless File.directory?(dir)

          effective = app.config.respond_to?(:all_eager_load_paths) ? app.config.all_eager_load_paths : app.config.eager_load_paths
          app.config.eager_load_paths << dir unless effective.include?(dir)
        end
      end

      initializer "view_component.atomix.helper" do
        ActiveSupport.on_load(:action_view) { include ViewComponent::Atomix::Helper }
      end

      initializer "view_component.atomix.reloader" do
        Rails.autoloaders.main.on_unload do |_name, owner, source|
          ViewComponent::Atomix.unload!(owner, source)
        end
        ActiveSupport::Reloader.before_class_unload do
          ViewComponent::Atomix.registry.clear_reloadable
        end
      end

      config.to_prepare do
        ViewComponent::Atomix.eager_load! if ViewComponent::Atomix.config.inline?
      end

      rake_tasks do
        load File.expand_path("tasks/build.rake", __dir__)
      end
    end
  end
end
