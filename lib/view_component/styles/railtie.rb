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
        ActiveSupport::Reloader.before_class_unload do
          # Style declarations under the main autoloader will be evaluated
          # again. Discard their old rules and class references first so
          # removed declarations cannot survive a reload.
          ViewComponent::Styles.registry.clear
          ViewComponent::Styles.includers.clear
          ViewComponent::Styles.dynamic_styles.clear
        end
      end

      config.to_prepare do
        app = Rails.application
        reloading = app.config.respond_to?(:reloading_enabled?) ? app.config.reloading_enabled? : !app.config.cache_classes
        ViewComponent::Styles.eager_load! if reloading
      end

      rake_tasks do
        load File.expand_path("tasks/build.rake", __dir__)
      end
    end
  end
end
