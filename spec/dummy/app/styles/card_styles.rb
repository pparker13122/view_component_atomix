# frozen_string_literal: true

module CardStyles
  CARD = ViewComponent::Styles.create(
    root: { padding: 24, border_radius: 8, background: Brand::VARS.surface },
    title: { font_size: 20, font_weight: 600 }
  )

  PAGE = ViewComponent::Styles.create(
    body: { margin: 0, font_family: "system-ui, sans-serif" }
  )
end
