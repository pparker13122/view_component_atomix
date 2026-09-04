# frozen_string_literal: true

module ViewComponent
  module Styles
    class DeclarationQueue
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
