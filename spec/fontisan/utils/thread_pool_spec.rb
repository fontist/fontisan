# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/fontisan/utils/thread_pool"

RSpec.describe Fontisan::Utils::ThreadPool do
  describe "#initialize" do
    it "creates thread pool with specified size" do
      pool = described_class.new(4)
      expect(pool).to be_a(described_class)
      pool.shutdown
    end
  end

  describe "#schedule" do
    it "executes scheduled job" do
      pool = described_class.new(2)
      future = pool.schedule { 42 }
      expect(future.value).to eq(42)
      pool.shutdown
    end

    it "executes multiple jobs in parallel" do
      pool = described_class.new(4)
      futures = 10.times.map do |i|
        pool.schedule { i * 2 }
      end

      results = futures.map(&:value)
      expect(results).to eq([0, 2, 4, 6, 8, 10, 12, 14, 16, 18])
      pool.shutdown
    end

    it "handles job errors" do
      pool = described_class.new(2)
      future = pool.schedule { raise "Test error" }

      expect { future.value }.to raise_error(RuntimeError, "Test error")
      pool.shutdown
    end
  end

  describe "#shutdown" do
    it "completes all queued jobs before shutdown" do
      pool = described_class.new(2)
      results = []
      mutex = Mutex.new

      futures = 5.times.map do |i|
        pool.schedule do
          sleep 0.01
          mutex.synchronize { results << i }
          i
        end
      end

      pool.shutdown
      expect(results.size).to eq(5)
    end

    it "allows threads to join after shutdown" do
      pool = described_class.new(2)
      pool.shutdown
      # Should not hang
      expect(true).to be true
    end
  end
end

RSpec.describe Fontisan::Utils::Future do
  describe "#set_value and #value" do
    it "retrieves set value" do
      future = described_class.new
      Thread.new { future.set_value(42) }
      expect(future.value).to eq(42)
    end

    it "blocks until value is set" do
      future = described_class.new
      result = nil

      thread = Thread.new do
        result = future.value
      end

      sleep 0.01
      expect(result).to be_nil

      future.set_value(:done)
      thread.join
      expect(result).to eq(:done)
    end
  end

  describe "#set_error and #value" do
    it "raises error when accessed" do
      future = described_class.new
      error = StandardError.new("Test error")
      Thread.new { future.set_error(error) }

      expect { future.value }.to raise_error(StandardError, "Test error")
    end
  end

  describe "#completed?" do
    it "returns false initially" do
      future = described_class.new
      expect(future.completed?).to be false
    end

    it "returns true after value is set" do
      future = described_class.new
      future.set_value(42)
      expect(future.completed?).to be true
    end

    it "returns true after error is set" do
      future = described_class.new
      future.set_error(StandardError.new("error"))
      expect(future.completed?).to be true
    end
  end
end
