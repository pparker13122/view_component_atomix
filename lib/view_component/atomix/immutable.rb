# frozen_string_literal: true

module ViewComponent
  module Atomix
    # Value objects own their containers and strings. Domain objects stored in
    # sheets (including callable dynamic styles) retain their own lifecycle.
    module Immutable
      module_function

      def copy(value)
        case value
        when Hash then value.to_h { |key, item| [copy(key), copy(item)] }.freeze
        when Array then value.map { |item| copy(item) }.freeze
        when String then value.frozen? ? value : value.dup.freeze
        else value
        end
      end
    end
  end
end
