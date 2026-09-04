# frozen_string_literal: true

require "ripper"

module ViewComponent
  module Styles
    module DynamicProperties
      class Unsupported < ArgumentError; end

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

      SOURCE_CACHE_LIMIT = 128

      module_function

      @cache = {}
      @cache_mutex = Mutex.new

      def extract(fn, name:, set:)
        path, line = fn.source_location
        raise unsupported(name, set, "source is unavailable") unless path && File.file?(path)

        lambdas = parsed_source(path)
        raise unsupported(name, set, "source could not be parsed") unless lambdas

        candidates = lambdas.fetch(line, [])
        if candidates.length != 1
          detail = candidates.empty? ? "lambda could not be located at #{path}:#{line}" :
                                      "multiple lambdas start at #{path}:#{line}; put each on its own line"
          raise unsupported(name, set, detail)
        end

        properties_from(candidates.first, name, set)
      rescue Errno::ENOENT, Errno::EACCES => e
        raise unsupported(name, set, e.message)
      end

      def parsed_source(path)
        stat = File.stat(path)
        cache_key = [stat.mtime.to_f, stat.size]
        @cache_mutex.synchronize do
          cached = @cache[path]
          return cached.last if cached&.first == cache_key

          parser = SourceParser.new(File.read(path), path)
          parsed = parser.parse && parser.lambdas
          @cache.shift if !@cache.key?(path) && @cache.size >= SOURCE_CACHE_LIMIT
          @cache[path] = [cache_key, parsed]
          parsed
        end
      end

      def properties_from(lambda_node, name, set)
        statements = lambda_node[2]
        statements = statements[1] if statements&.first == :bodystmt
        meaningful = Array(statements).reject { |node| node.is_a?(Array) && node.first == :void_stmt }
        body = meaningful.one? ? meaningful.first : nil
        body = body[1] if body&.first == :paren

        unless body&.first == :hash
          raise unsupported(name, set, "lambda must return one literal Hash")
        end

        associations = body.dig(1, 1) || []
        associations.map do |association|
          unless association.is_a?(Array) && association.first == :assoc_new
            raise unsupported(name, set, "hash splats and computed entries are not supported")
          end

          literal_key(association[1]) ||
            raise(unsupported(name, set, "every property key must be a literal label, Symbol, or String"))
        end.map { |key| Property.normalize_key(key) }.uniq.freeze
      end

      def literal_key(node)
        return unless node.is_a?(Array)

        case node.first
        when :@label
          node[1].delete_suffix(":")
        when :symbol_literal
          token = find_token(node, :@ident) || find_token(node, :@op) || find_token(node, :@kw)
          token&.[](1)
        when :string_literal
          contents = node[1].drop(1)
          return unless contents.all? { |part| part.first == :@tstring_content }

          quote = node[2] || '"'
          return unless ["'", '"'].include?(quote) || quote.match?(/\A%(?:q|Q)?.\z/)

          closing = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }.fetch(quote[-1], quote[-1])
          literal = quote + contents.map { |part| part[1] }.join + closing
          # Reparse the isolated expression before decoding Ruby escapes. Only
          # a single string containing text tokens is evaluated; interpolation,
          # calls, and extra expressions are never allowed through this boundary.
          tree = Ripper.sexp(literal)
          expressions = tree&.[](1)
          return unless expressions&.one? && expressions.first.first == :string_literal
          return unless expressions.first[1].drop(1).all? { |part| part.first == :@tstring_content }

          eval(literal, TOPLEVEL_BINDING, __FILE__, __LINE__) # rubocop:disable Security/Eval
        end
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

      def unsupported(name, set, detail)
        Unsupported.new(
          "Dynamic style #{name}.#{set} cannot be compiled: #{detail}. " \
          "Return one literal Hash with static property keys, or declare " \
          "`trait :#{set}, dynamic: %i[...], using: -> { ... }`."
        )
      end
    end
  end
end
