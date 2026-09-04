# frozen_string_literal: true

module ViewComponent
  module Styles
    module ThemeCompiler
      # A variable group may span multiple style_vars declarations.
      def self.compile(id, names, overrides)
        digest_input = overrides.sort_by { |k, _| k.to_s }.map { |k, v| "#{k}=#{v.inspect}" }
        class_name = Hashing.class_name("theme", id, digest_input)
        Styles.registry.transaction do
          overrides.each do |key, value|
            Vars.register(".#{class_name}", names.fetch(key.to_sym), value)
          end
        end
        Style.new({ "theme:#{id}" => [class_name] })
      end
    end
  end
end
