# frozen_string_literal: true

module ViewComponent
  module Atomix
    module DynamicProperties
      class SourceCache
        LIMIT = 128

        def initialize
          @cache = {}
          @mutex = Mutex.new
        end

        def fetch(path)
          stat = File.stat(path)
          cache_key = [stat.mtime.to_f, stat.size]
          @mutex.synchronize do
            cached = @cache[path]
            return cached.last if cached&.first == cache_key

            parser = SourceParser.new(File.read(path), path)
            parsed = parser.parse && parser.lambdas
            @cache.shift if !@cache.key?(path) && @cache.size >= LIMIT
            @cache[path] = [cache_key, parsed]
            parsed
          end
        end
      end
    end
  end
end
