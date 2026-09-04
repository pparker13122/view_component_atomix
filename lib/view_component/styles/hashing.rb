# frozen_string_literal: true

require "digest/sha1"

module ViewComponent
  module Styles
    module Hashing
      # Twelve base-36 characters retain roughly 62 bits of SHA1. This keeps
      # selectors compact while making collisions impractical for application
      # sized stylesheets.
      LENGTH = 12

      module_function

      def digest(*parts)
        input = parts.map { |part| serialize(part) }.join
        Digest::SHA1.hexdigest(input).to_i(16).to_s(36)[0, LENGTH]
      end

      def serialize(value)
        case value
        when Array
          encoded = value.map { |item| serialize(item) }.join
          "a#{value.length}:#{encoded.bytesize}:#{encoded}"
        when Symbol
          serialize_scalar("y", value.to_s)
        when nil
          "n"
        else
          serialize_scalar("s", value.to_s)
        end
      end

      def serialize_scalar(type, value)
        "#{type}#{value.bytesize}:#{value}"
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
