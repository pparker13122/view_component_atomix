# frozen_string_literal: true

module ToastComponentStyles
  include ViewComponent::Atomix

  style_vars gap: 6

  theme primary: "#123456"

  styles root: { display: :flex, gap: styles.gap, padding: 12 }
end
