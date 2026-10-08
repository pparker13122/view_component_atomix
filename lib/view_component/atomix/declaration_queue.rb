# frozen_string_literal: true

module ViewComponent
  module Atomix
    class DeclarationQueue
      MAX_DRAIN_PASSES = 1000
      StyleDeclaration = Struct.new(:block, :source, keyword_init: true)
      VariableDeclaration = Struct.new(:label, :block, :source, keyword_init: true)
      ThemeDeclaration = Struct.new(:vars, :overrides, :block, :source, keyword_init: true)

      def initialize
        @pending = []
      end

      def <<(declaration)
        @pending << declaration
        self
      end

      # Successful declarations stay consumed. On failure, retry the failed
      # declaration and its successors before work enqueued during evaluation.
      # Owners serialize access with the reentrant resolution monitor.
      def drain
        ResolutionSession.with do |session|
          session.nested do
            until @pending.empty?
              session.consume!
              drain_batch { |declaration| yield declaration }
            end
          end
        end
      end

      private

      def drain_batch
        pending = @pending
        @pending = []
        pending.each_with_index do |declaration, index|
          begin
            yield declaration
          rescue StandardError
            @pending = pending.drop(index) + @pending
            raise
          end
        end
      end
    end
  end
end
