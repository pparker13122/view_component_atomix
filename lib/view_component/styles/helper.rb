# frozen_string_literal: true

module ViewComponent
  module Styles
    module Helper
      def sx(*styles)
        ViewComponent::Styles.sx(*styles)
      end

      def sx_attrs(*styles)
        ViewComponent::Styles.props(*styles)
      end

      def view_component_styles_tag(**options)
        config = ViewComponent::Styles.config

        if config.inline?
          content_tag(:style, ViewComponent::Styles.registry.to_css.html_safe,
                      { data: { view_component_styles: true } }.merge(options))
        else
          stylesheet_link_tag(File.basename(config.output_path, ".css"),
                              { "data-turbo-track": "reload" }.merge(options))
        end
      end
    end
  end
end
