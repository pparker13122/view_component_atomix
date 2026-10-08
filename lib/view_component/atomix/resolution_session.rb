# frozen_string_literal: true

module ViewComponent
  module Atomix
    # One logical read, including nested owners, queue drains and cache rebuilds.
    # Declaration revisions track writes; frames separately track reads of work
    # that has not finished yet. Neither kind of instability may publish a cache.
    class ResolutionSession
      MAX_DEPTH = 64
      MAX_STABILITY_PASSES = 32
      Frame = Struct.new(:provisional)

      def self.with
        existing = Thread.current[:view_component_atomix_resolution]
        return yield existing if existing

        begin
          session = new
          Thread.current[:view_component_atomix_resolution] = session
          yield session
        ensure
          Thread.current[:view_component_atomix_resolution] = nil
        end
      end

      def initialize
        @frames = []
        @depth = 0
        @passes = 0
      end

      def resolving?
        !@frames.empty?
      end

      def provisional!
        @frames.each { |frame| frame.provisional = true }
      end

      def frame
        nested do
          current = Frame.new(false)
          @frames << current
          begin
            yield current
          ensure
            @frames.pop
          end
        end
      end

      def nested
        if @depth >= MAX_DEPTH
          raise ArgumentError, "Style resolution exceeds the nesting limit (#{MAX_DEPTH})"
        end

        @depth += 1
        begin
          yield
        ensure
          @depth -= 1
        end
      end

      def consume!
        @passes += 1
        if @passes > DeclarationQueue::MAX_DRAIN_PASSES
          raise ArgumentError, "Style declarations keep adding work during resolution"
        end
      end
    end
  end
end
