# frozen_string_literal: true

require "digest/sha1"

module ViewComponent
  module Styles
    module Hashing
      LENGTH = 8

      module_function

      def digest(*parts)
        Digest::SHA1.hexdigest(parts.join("|")).to_i(16).to_s(36)[0, LENGTH]
      end

      def class_name(property, value, conditions = [])
        "#{Styles.config.class_prefix}#{digest(property, value, *conditions)}"
      end

      def var_name(*parts)
        "--#{Styles.config.class_prefix}#{digest(*parts)}"
      end
    end
  end
end
