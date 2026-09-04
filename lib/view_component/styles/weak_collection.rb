# frozen_string_literal: true

require "weakref"

module ViewComponent
  module Styles
    class WeakCollection
      include Enumerable

      def initialize
        @references = []
        @mutex = Mutex.new
      end

      def <<(object)
        @mutex.synchronize do
          compact!
          @references << WeakRef.new(object) unless @references.any? { |reference| dereference(reference)&.equal?(object) }
        end
        self
      end

      def each
        return enum_for(:each) unless block_given?

        objects = @mutex.synchronize do
          compact!
          @references.filter_map { |reference| dereference(reference) }
        end
        objects.each { |object| yield object }
        self
      end

      def delete_if
        @mutex.synchronize do
          @references.delete_if do |reference|
            object = dereference(reference)
            object.nil? || yield(object)
          end
        end
        self
      end

      def clear
        @mutex.synchronize { @references.clear }
        self
      end

      private

      def compact!
        @references.select!(&:weakref_alive?)
      end

      def dereference(reference)
        reference.__getobj__
      rescue WeakRef::RefError
        nil
      end
    end
  end
end
