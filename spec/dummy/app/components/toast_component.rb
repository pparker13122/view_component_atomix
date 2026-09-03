# frozen_string_literal: true

class ToastComponent < ViewComponent::Base
  include ViewComponent::Styles

  styles do
    trait :tone, color: styles.primary
    trait :cta, :root, font_weight: 700
  end

  erb_template <<~ERB
    <div <%= styles.props(theme, styles.root, styles.tone) %>><%= content %></div>
  ERB
end
