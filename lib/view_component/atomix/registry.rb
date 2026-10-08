# frozen_string_literal: true

module ViewComponent
  module Atomix
    class Registry
      Registration = Struct.new(:rule, :source, keyword_init: true)
      RootReplacement = Struct.new(:property, :source, keyword_init: true)
      Transaction = Struct.new(:registrations, :callbacks, keyword_init: true) do
        def initialize(registrations: [], callbacks: [])
          super
        end

        def absorb(other)
          registrations.concat(other.registrations)
          callbacks.concat(other.callbacks)
        end
      end

      def initialize
        @mutex = Mutex.new
        @rules = {}
        @root_rules = {}
        @css = nil
      end

      def add(rule)
        entry = Registration.new(rule: rule, source: registration_source)
        if (pending = transactions.last)
          pending.registrations << entry
        else
          commit(Transaction.new(registrations: [entry]))
        end
        rule
      end

      def after_commit(&block)
        if (pending = transactions.last)
          pending.callbacks << block
        else
          block.call
        end
      end

      # Record the replacement in declaration order, in the same transaction as
      # its new rules. Empty assignments must also remove the old branches.
      def replace_root(property)
        entry = RootReplacement.new(property: property, source: registration_source)
        if (pending = transactions.last)
          pending.registrations << entry
        else
          commit(Transaction.new(registrations: [entry]))
        end
      end

      # Nested operations join their declaration. A separately resolved owner
      # uses independent: true because its successful result is cached even if
      # the declaration which requested it subsequently fails.
      def transaction(independent: false)
        pending = Transaction.new
        transactions << pending
        result = yield
        if transactions.length > 1 && !independent
          transactions[-2].absorb(pending)
        else
          commit(pending)
        end
        result
      ensure
        stack = transactions
        stack.pop
        Thread.current[:view_component_atomix_transactions].delete(object_id) if stack.empty?
      end

      def with_source(path)
        previous = Thread.current[:view_component_atomix_source]
        Thread.current[:view_component_atomix_source] = path
        yield
      ensure
        Thread.current[:view_component_atomix_source] = previous
      end

      def clear_reloadable
        roots = reloadable_roots
        @mutex.synchronize do
          @rules.delete_if do |_, sources|
            sources.delete_if { |source| source && roots.any? { |root| source.start_with?(root) } }
            sources.empty?
          end
          @root_rules.each_value { |rules| rules.select! { |rule| @rules.key?(rule) } }
          @root_rules.delete_if { |_, rules| rules.empty? }
          @css = nil
        end
      end

      def clear
        @mutex.synchronize do
          @rules.clear
          @root_rules.clear
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
        Thread.current[:view_component_atomix_transactions] ||= {}
        Thread.current[:view_component_atomix_transactions][object_id] ||= []
      end

      def commit(transaction)
        @mutex.synchronize do
          transaction.registrations.each do |entry|
            if entry.is_a?(RootReplacement)
              release_root(entry.property, entry.source)
            else
              register(entry.rule, entry.source)
            end
          end
          @css = nil unless transaction.registrations.empty?
        end
        transaction.callbacks.each(&:call)
      end

      def register(rule, source)
        unless rule.selector == ":root"
          (@rules[rule] ||= Set.new).add(source)
          return
        end

        release_root(rule.property, source) { |existing| existing.conditions == rule.conditions }
        @rules[rule] = (@rules.delete(rule) || Set.new).add(source)
        (@root_rules[rule.property] ||= Set.new).add(rule)
      end

      # Root variables are assignments, unlike content-addressed atoms. Remove
      # only this source's previous assignment; other owners may still use it.
      def release_root(property, source)
        rules = @root_rules[property]
        return unless rules

        rules.delete_if do |rule|
          next false if block_given? && !yield(rule)

          sources = @rules.fetch(rule)
          sources.delete(source)
          next false unless sources.empty?

          @rules.delete(rule)
          true
        end
        @root_rules.delete(property) if rules.empty?
      end

      def reloadable_roots
        return [] unless defined?(Rails) && Rails.respond_to?(:autoloaders) && Rails.application

        Rails.autoloaders.main.dirs.map { |dir| "#{File.expand_path(dir)}/" }
      end

      def registration_source
        source = Thread.current[:view_component_atomix_source]
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

        unless Atomix.config.use_layers
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
        "#{Atomix.config.class_prefix}#{priority}"
      end
    end
  end
end
