# frozen_string_literal: true

module ViewComponent
  module Styles
    class Registry
      def initialize
        @mutex = Mutex.new
        @rules = {}
        @css = nil
      end

      def add(rule)
        entry = [rule, registration_source]
        if (pending = transactions.last)
          pending << entry
        else
          commit([entry])
        end
        rule
      end

      def after_commit(&block)
        if (pending = transactions.last)
          pending << block
        else
          block.call
        end
      end

      # Nested operations join their declaration. A separately resolved owner
      # uses independent: true because its successful result is cached even if
      # the declaration which requested it subsequently fails.
      def transaction(independent: false)
        pending = []
        transactions << pending
        result = yield
        if transactions.length > 1 && !independent
          transactions[-2].concat(pending)
        else
          commit(pending)
        end
        result
      ensure
        stack = transactions
        stack.pop
        Thread.current[:view_component_styles_transactions].delete(object_id) if stack.empty?
      end

      def with_source(path)
        previous = Thread.current[:view_component_styles_source]
        Thread.current[:view_component_styles_source] = path
        yield
      ensure
        Thread.current[:view_component_styles_source] = previous
      end

      def clear_reloadable
        roots = reloadable_roots
        @mutex.synchronize do
          @rules.delete_if do |_, sources|
            sources.delete_if { |source| source && roots.any? { |root| source.start_with?(root) } }
            sources.empty?
          end
          @css = nil
        end
      end

      def clear
        @mutex.synchronize do
          @rules.clear
          @css = nil
        end
      end

      def rules
        @mutex.synchronize { @rules.keys }
      end

      def size
        @mutex.synchronize { @rules.size }
      end

      def to_css
        @mutex.synchronize do
          @css ||= build_css(@rules.keys)
        end
      end

      private

      def transactions
        Thread.current[:view_component_styles_transactions] ||= {}
        Thread.current[:view_component_styles_transactions][object_id] ||= []
      end

      def commit(entries)
        @mutex.synchronize do
          entries.reject { |entry| entry.is_a?(Proc) }.each do |rule, source|
            # Root variables are assignments, unlike content-addressed atoms.
            if rule.selector == ":root"
              @rules.delete_if do |existing, sources|
                next false unless existing.selector == rule.selector && existing.property == rule.property && existing.conditions == rule.conditions
                sources.delete(source)
                sources.empty?
              end
            end
            sources = rule.selector == ":root" ? @rules.delete(rule) : @rules[rule]
            @rules[rule] = (sources || Set.new).add(source)
          end
          @css = nil unless entries.empty?
        end
        entries.grep(Proc).each(&:call)
      end

      def reloadable_roots
        return [] unless defined?(Rails) && Rails.respond_to?(:autoloaders)

        Rails.autoloaders.main.dirs.map { |dir| "#{File.expand_path(dir)}/" }
      end

      def registration_source
        source = Thread.current[:view_component_styles_source]
        return File.expand_path(source) if source

        roots = reloadable_roots
        caller_locations.each do |location|
          path = File.expand_path(location.absolute_path || location.path)
          return path if roots.any? { |root| path.start_with?(root) }
        end
        nil
      end

      def build_css(rules)
        sorted = rules.sort_by.with_index { |rule, i| [rule.priority, i] }

        unless Styles.config.use_layers
          return sorted.map(&:to_css).join("\n")
        end

        groups = sorted.group_by(&:priority)
        return "" if groups.empty?

        header = "@layer #{groups.keys.map { |p| layer_name(p) }.join(',')};"
        body = groups.map do |priority, group|
          "@layer #{layer_name(priority)}{\n#{group.map(&:to_css).join("\n")}\n}"
        end
        [header, *body].join("\n")
      end

      def layer_name(priority)
        "#{Styles.config.class_prefix}#{priority}"
      end
    end
  end
end
