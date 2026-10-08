# frozen_string_literal: true

class ButtonComponent < ViewComponent::Base
  include ViewComponent::Atomix

  styles base: {
           padding: "8px 16px",
           border_radius: 4,
           border: "none",
           background: { default: "#fff", hover: "#eee" },
           font_size: { default: 16, md: 14 }
         },
         primary: { background: styles.primary, color: "#fff" },
         secondary: { background: "transparent", color: styles.primary },
         sized: ->(w) { { width: w } }

  def initialize(variant: :primary, width: nil, styles: nil)
    @variant = variant
    @width = width
    @extra = styles
  end

  erb_template <<~ERB
    <button <%= styles.props(styles.base, styles[@variant], styles.sized(@width), @extra) %>><%= content %></button>
  ERB
end
