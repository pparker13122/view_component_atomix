# frozen_string_literal: true

module ViewComponent
  module Atomix
    module Helper
      include AttributeHelpers

      def view_component_atomix_tag(**options)
        config = ViewComponent::Atomix.config

        if config.inline?
          content_tag(:style, ViewComponent::Atomix.registry.to_css.html_safe,
                      { data: { view_component_atomix: true } }.merge(options))
        else
          stylesheet_link_tag(stylesheet_logical_path(config.output_path),
                              { "data-turbo-track": "reload" }.merge(options))
        end
      end

      private

      def stylesheet_logical_path(output_path)
        path = output_path.to_s.delete_suffix(".css")
        path = path.delete_prefix("#{Rails.root}/") if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
        path.sub(%r{\Aapp/assets/(?:builds|stylesheets)/}, "")
      end
    end
  end
end
