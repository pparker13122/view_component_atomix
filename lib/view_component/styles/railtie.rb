# frozen_string_literal: true

require "rails/railtie"

module ViewComponent
  module Styles
    class Railtie < Rails::Railtie
      config.before_configuration do |app|
        app.config.paths.add "app/components/styles", eager_load: true
        app.config.view_component.styles = ViewComponent::Styles.config
        ViewComponent::Styles.config.inline = !Rails.env.production?
      end

      initializer "view_component.styles.helper" do
        ActiveSupport.on_load(:action_view) { include ViewComponent::Styles::Helper }
      end

      initializer "view_component.styles.reloader" do
        Rails.autoloaders.main.on_unload do |_name, owner, source|
          ViewComponent::Styles.unload!(owner, source)
        end
        ActiveSupport::Reloader.before_class_unload do
          ViewComponent::Styles.registry.clear_reloadable
        end
      end

      config.to_prepare do
        ViewComponent::Styles.eager_load! if ViewComponent::Styles.config.inline?
      end

      rake_tasks do
        load File.expand_path("tasks/build.rake", __dir__)
      end
    end
  end
end
