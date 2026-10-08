# frozen_string_literal: true

require "ripper"

module ViewComponent
  module Atomix
    module DynamicProperties
      # Associate each lambda with its opening token while parsing, before
      # modifier expressions can reorder nodes in the resulting syntax tree.
      class SourceParser < Ripper::SexpBuilderPP
        attr_reader :lambdas

        def initialize(*)
          super
          @lambda_lines = []
          @lambdas = {}
          @string_quotes = []
        end

        def on_heredoc_beg(token)
          @string_quotes << token
          super
        end

        def on_tstring_beg(token)
          @string_quotes << token
          super
        end

        def on_symbeg(token)
          # Bare symbols have no string body; quoted and percent symbols do.
          @string_quotes << token unless token == ":"
          super
        end

        def on_dyna_symbol(content)
          node = super
          node << @string_quotes.pop
          node
        end

        def on_string_literal(content)
          node = super
          node << @string_quotes.pop
          node
        end

        def on_tlambda(token)
          @lambda_lines << lineno
          super
        end

        def on_lambda(params, body)
          node = super
          (@lambdas[@lambda_lines.pop] ||= []) << node
          node
        end
      end
    end
  end
end
