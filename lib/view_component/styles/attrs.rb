# frozen_string_literal: true

module ViewComponent
  module Styles
    class Attrs < Hash
      def to_s
        html = map { |name, value| "#{name}=\"#{ERB::Util.html_escape(value)}\"" }.join(" ")
        ActiveSupport::SafeBuffer.new(html)
      end
    end
  end
end
