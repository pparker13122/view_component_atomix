# frozen_string_literal: true

module Brand
  VARS = ViewComponent::Styles.define_vars(
    primary: "#0055ff",
    surface: { default: "#ffffff", dark: "#111111" }
  )

  HIGH_CONTRAST = ViewComponent::Styles.create_theme(VARS, primary: "#000000")
end
