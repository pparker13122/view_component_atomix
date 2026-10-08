# frozen_string_literal: true

require "ripper"

module ViewComponent
  module Atomix
    module DynamicProperties
      module LiteralKey
        module_function

        def read(node)
          return unless node.is_a?(Array)

          case node.first
          when :@label
            node[1].delete_suffix(":")
          when :symbol_literal
            token = find_token(node, :@ident) || find_token(node, :@op) || find_token(node, :@kw)
            token&.[](1)
          when :string_literal, :dyna_symbol
            decode_literal_string(node)
          end
        end

        def decode_literal_string(node)
          contents = node[1].drop(1)
          return unless text_tokens?(contents)

          quote = node[2] || '"'
          quote = quote.delete_prefix(":") if quote.start_with?(":")
          quote = quote.sub(/\A%s/, "%q")
          literal = reconstruct_string(quote, contents)
          return unless literal

          # Reparse immediately before evaluating: only one text-only string is
          # allowed. Interpolation, calls, and extra expressions cannot pass.
          expressions = Ripper.sexp(literal)&.[](1)
          return unless expressions&.one? && expressions.first.first == :string_literal
          return unless text_tokens?(expressions.first[1].drop(1))

          eval(literal, TOPLEVEL_BINDING, __FILE__, __LINE__) # rubocop:disable Security/Eval
        end

        def reconstruct_string(quote, contents)
          return unless ["'", '"'].include?(quote) || quote.match?(/\A%(?:q|Q)?.\z/)

          closing = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }.fetch(quote[-1], quote[-1])
          quote + contents.map { |part| part[1] }.join + closing
        end

        def text_tokens?(contents)
          contents.all? { |part| part.first == :@tstring_content }
        end

        def find_token(node, type)
          return node if node.is_a?(Array) && node.first == type
          return unless node.is_a?(Array)

          node.each do |child|
            found = find_token(child, type)
            return found if found
          end
          nil
        end
      end
    end
  end
end
