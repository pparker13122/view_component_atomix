# frozen_string_literal: true

class PanelComponent < ViewComponent::Base
  include ViewComponent::Styles
  include DarkModeTheme

  style_vars gap: 12, accent: "#ff6600"

  theme accent: "#00cc66"

  styles root: { display: "grid", gap: styles.gap, background: styles.surface, border_color: styles.accent }

  def initialize(dark: false)
    @dark = dark
  end

  erb_template <<~ERB
    <section <%= styles.props(@dark ? dark_mode_theme : theme, styles.root) %>><%= content %></section>
  ERB
end
