# frozen_string_literal: true

module Brand
  VARS = ViewComponent::Atomix.define_vars(
    primary: "#0055ff",
    surface: { default: "#ffffff", dark: "#111111" }
  )

  HIGH_CONTRAST = ViewComponent::Atomix.create_theme(VARS, primary: "#000000")
end
