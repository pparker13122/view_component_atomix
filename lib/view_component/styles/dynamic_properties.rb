# frozen_string_literal: true

require "ripper"

module ViewComponent
  module Styles
    module DynamicProperties
      class Unsupported < ArgumentError; end

      module_function

      def extract(fn, name:, set:)
        path, line = fn.source_location
        raise unsupported(name, set, "source is unavailable") unless path && File.file?(path)

        tree = Ripper.sexp(File.read(path), path)
        raise unsupported(name, set, "source could not be parsed") unless tree

        candidates = find_lambdas(tree).select { |node| first_line(node) == line }
        if candidates.length != 1
          detail = candidates.empty? ? "lambda could not be located at #{path}:#{line}" :
                                      "multiple lambdas start at #{path}:#{line}; put each on its own line"
          raise unsupported(name, set, detail)
        end

        properties_from(candidates.first, name, set)
      rescue Errno::ENOENT, Errno::EACCES => e
        raise unsupported(name, set, e.message)
      end

      def find_lambdas(node, found = [])
        return found unless node.is_a?(Array)

        found << node if node.first == :lambda
        node.each { |child| find_lambdas(child, found) if child.is_a?(Array) }
        found
      end

      def first_line(node)
        locations = []
        collect_locations(node, locations)
        locations.map(&:first).min
      end

      def collect_locations(node, locations)
        return unless node.is_a?(Array)

        if node.first.to_s.start_with?("@") && node[2].is_a?(Array)
          locations << node[2]
        else
          node.each { |child| collect_locations(child, locations) }
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
          content = node.dig(1, 1)
          content[1] if content&.first == :@tstring_content
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
