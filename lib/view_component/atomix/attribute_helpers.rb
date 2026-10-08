# frozen_string_literal: true

module ViewComponent
  module Atomix
    module AttributeHelpers
      def sx(*styles)
        ViewComponent::Atomix.sx(*styles)
      end

      def sx_attrs(*styles)
        ViewComponent::Atomix.props(*styles)
      end
    end
  end
end
