# frozen_string_literal: true

module PillStyles
  include ViewComponent::Atomix

  styles pill: { display: :inline_block, border_radius: 999, padding: "2px 8px", color: "#333" }
end
