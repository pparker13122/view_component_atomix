# frozen_string_literal: true

require_relative "dynamic_properties/source_parser"
require_relative "dynamic_properties/source_cache"
require_relative "dynamic_properties/literal_key"

module ViewComponent
  module Atomix
    module DynamicProperties
      class Unsupported < ArgumentError; end

      SOURCE_CACHE = SourceCache.new

      module_function

      def extract(fn, name:, set:)
        path, line = fn.source_location
        raise unsupported(name, set, "source is unavailable") unless path && File.file?(path)

        lambdas = SOURCE_CACHE.fetch(path)
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

      def properties_from(lambda_node, name, set)
        body = returned_hash(lambda_node, name, set)
        hash_associations(body).map do |association|
          unless association.is_a?(Array) && association.first == :assoc_new
            raise unsupported(name, set, "hash splats and computed entries are not supported")
          end

          LiteralKey.read(association[1]) ||
            raise(unsupported(name, set, "every property key must be a literal label, Symbol, or String"))
        end.map { |key| Property.normalize_key(key) }.uniq.freeze
      end

      def returned_hash(lambda_node, name, set)
        statements = lambda_node[2]
        statements = statements[1] if statements&.first == :bodystmt
        meaningful = Array(statements).reject { |node| node.is_a?(Array) && node.first == :void_stmt }
        body = meaningful.one? ? meaningful.first : nil
        body = body[1] if body&.first == :paren

        unless body&.first == :hash
          raise unsupported(name, set, "lambda must return one literal Hash")
        end

        body
      end

      def hash_associations(hash_node)
        # Ripper represents a hash as [:hash, [:assoclist_from_args, entries]].
        hash_node.dig(1, 1) || []
      end

      def unsupported(name, set, detail)
        Unsupported.new(
          "Dynamic trait #{name}.#{set} cannot be compiled: #{detail}. " \
          "Return one literal Hash with static property keys, or declare " \
          "`trait :#{set}, dynamic: %i[...], using: -> { ... }`."
        )
      end
    end
  end
end
