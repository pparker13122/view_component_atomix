# frozen_string_literal: true

class PillComponent < ViewComponent::Base
  include PillStyles

  styles tone: { color: styles.primary }

  erb_template <<~ERB
    <span <%= styles.props(pill_styles.pill, styles.tone) %>><%= content %></span>
  ERB
end
