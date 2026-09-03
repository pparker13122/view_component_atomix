# frozen_string_literal: true

module BadgeStyles
  BADGE = ViewComponent::Styles.create(
    root: { display: :inline_block, padding: "2px 6px", font_size: 12, color: Brand::VARS.primary }
  )
end
