# frozen_string_literal: true

class PrimaryButtonComponent < ButtonComponent
  styles base: { padding: "12px 24px" },
         large: { font_size: 20 }

  erb_template <<~ERB
    <button <%= styles.props(styles.base, styles[@variant], styles.large) %>><%= content %></button>
  ERB
end
