# frozen_string_literal: true

class LazyComponent < ViewComponent::Base
  include ViewComponent::Styles

  styles do
    { root: { display: "grid", gap: 12, color: Brand::VARS.primary } }
  end

  erb_template <<~ERB
    <section <%= styles.props(styles.root) %>>lazy</section>
  ERB
end
