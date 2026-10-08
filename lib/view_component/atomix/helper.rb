# frozen_string_literal: true

module ViewComponent
  module Atomix
    module Helper
      include AttributeHelpers

      def view_component_atomix_tag(**options)
        config = ViewComponent::Atomix.config
        options[:nonce] = content_security_policy_nonce if options[:nonce] == true

        if config.inline?
          css = ViewComponent::Atomix.registry.to_css
          css = css.gsub("</", "<\\/") if css.include?("</")
          content_tag(:style, css.html_safe, { "data-view-component-atomix": "true" }.merge(options))
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
