# frozen_string_literal: true

module Fontisan
  module Utils
    # Simple thread pool implementation
    #
    # Manages a fixed number of worker threads for parallel job execution.
    # Jobs are queued and processed by available workers.
    #
    # @example Basic usage
    #   pool = ThreadPool.new(4)
    #   future = pool.schedule { expensive_computation }
    #   result = future.value
    #   pool.shutdown
    class ThreadPool
      # Initialize thread pool
      #
      # @param size [Integer] Number of worker threads
      def initialize(size)
        @size = size
        @queue = Queue.new
        @threads = []
        @shutdown = false

        # Start worker threads
        @size.times do
          @threads << Thread.new { worker_loop }
        end
      end

      # Schedule a job for execution
      #
      # @yield Job to execute
      # @return [Future] Future object to retrieve result
      def schedule(&block)
        future = Future.new
        @queue << { block: block, future: future }
        future
      end

      # Shutdown thread pool
      #
      # Waits for all queued jobs to complete and stops workers.
      def shutdown
        @shutdown = true

        # Signal all threads to stop
        @size.times { @queue << :stop }

        # Wait for all threads to finish
        @threads.each(&:join)
      end

      private

      # Worker thread main loop
      def worker_loop
        loop do
          job = @queue.pop
          break if job == :stop

          begin
            result = job[:block].call
            job[:future].set_value(result)
          rescue StandardError => e
            job[:future].set_error(e)
          end
        end
      end
    end

    # Future object for async result retrieval
    #
    # Represents a computation that will complete in the future.
    # Provides blocking access to the eventual result or error.
    #
    # @example Basic usage
    #   future = Future.new
    #   Thread.new { future.set_value(42) }
    #   result = future.value  # Blocks until value is set
    class Future
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @completed = false
        @value = nil
        @error = nil
      end

      # Set the computed value
      #
      # @param value [Object] Result value
      def set_value(value)
        @mutex.synchronize do
          @value = value
          @completed = true
          @condition.signal
        end
      end

      # Set an error
      #
      # @param error [Exception] Error that occurred
      def set_error(error)
        @mutex.synchronize do
          @error = error
          @completed = true
          @condition.signal
        end
      end

      # Get the value, blocking until available
      #
      # @return [Object] Computed value
      # @raise [Exception] If computation failed
      def value
        @mutex.synchronize do
          @condition.wait(@mutex) until @completed

          raise @error if @error

          @value
        end
      end

      # Check if computation is complete
      #
      # @return [Boolean] True if complete
      def completed?
        @mutex.synchronize { @completed }
      end
    end
  end
end
