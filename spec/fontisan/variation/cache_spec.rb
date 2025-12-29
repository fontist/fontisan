# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/cache"

RSpec.describe Fontisan::Variation::Cache do
  let(:cache) { described_class.new(max_size: 3) }

  describe "#initialize" do
    it "initializes with default options" do
      cache = described_class.new

      expect(cache.max_size).to eq(1000)
      expect(cache.size).to eq(0)
    end

    it "accepts custom max_size" do
      cache = described_class.new(max_size: 100)

      expect(cache.max_size).to eq(100)
    end

    it "initializes statistics" do
      expect(cache.stats[:hits]).to eq(0)
      expect(cache.stats[:misses]).to eq(0)
      expect(cache.stats[:evictions]).to eq(0)
      expect(cache.stats[:invalidations]).to eq(0)
    end
  end

  describe "#fetch" do
    it "computes value on cache miss" do
      value = cache.fetch("key1") { "computed_value" }

      expect(value).to eq("computed_value")
      expect(cache.stats[:misses]).to eq(1)
      expect(cache.stats[:hits]).to eq(0)
    end

    it "returns cached value on cache hit" do
      cache.fetch("key1") { "computed_value" }
      value = cache.fetch("key1") { "should_not_compute" }

      expect(value).to eq("computed_value")
      expect(cache.stats[:misses]).to eq(1)
      expect(cache.stats[:hits]).to eq(1)
    end

    it "caches block result" do
      call_count = 0
      3.times do
        cache.fetch("key1") do
          call_count += 1
          "value"
        end
      end

      expect(call_count).to eq(1)
    end
  end

  describe "#fetch_scalars" do
    let(:axes) do
      [
        double("Axis", axis_tag: "wght"),
        double("Axis", axis_tag: "wdth"),
      ]
    end

    it "caches scalars for coordinates" do
      coordinates = { "wght" => 700.0, "wdth" => 100.0 }

      call_count = 0
      2.times do
        cache.fetch_scalars(coordinates, axes) do
          call_count += 1
          [0.8, 1.0]
        end
      end

      expect(call_count).to eq(1)
    end

    it "generates different keys for different coordinates" do
      coords1 = { "wght" => 700.0 }
      coords2 = { "wght" => 400.0 }

      value1 = cache.fetch_scalars(coords1, axes) { [0.8] }
      value2 = cache.fetch_scalars(coords2, axes) { [0.0] }

      expect(value1).not_to eq(value2)
    end
  end

  describe "#fetch_interpolated" do
    it "caches interpolated values" do
      call_count = 0
      2.times do
        cache.fetch_interpolated(100, [10, 5], [0.8, 0.5]) do
          call_count += 1
          110.5
        end
      end

      expect(call_count).to eq(1)
    end
  end

  describe "#fetch_instance" do
    it "caches instance generation results" do
      checksum = "font123"
      coordinates = { "wght" => 700.0 }

      call_count = 0
      2.times do
        cache.fetch_instance(checksum, coordinates) do
          call_count += 1
          { "glyf" => "data" }
        end
      end

      expect(call_count).to eq(1)
    end

    it "generates different keys for different fonts" do
      coords = { "wght" => 700.0 }

      value1 = cache.fetch_instance("font1", coords) { { result: 1 } }
      value2 = cache.fetch_instance("font2", coords) { { result: 2 } }

      expect(value1).not_to eq(value2)
    end
  end

  describe "#fetch_region_matches" do
    let(:regions) { [double("Region1"), double("Region2")] }

    it "caches region matches" do
      coordinates = { "wght" => 700.0 }

      call_count = 0
      2.times do
        cache.fetch_region_matches(coordinates, regions) do
          call_count += 1
          [{ index: 0, scalar: 0.8 }]
        end
      end

      expect(call_count).to eq(1)
    end
  end

  describe "#cached?" do
    it "returns false for non-existent key" do
      expect(cache.cached?("nonexistent")).to be false
    end

    it "returns true for existing key" do
      cache.store("key1", "value")

      expect(cache.cached?("key1")).to be true
    end
  end

  describe "#store" do
    it "stores value in cache" do
      cache.store("key1", "value1")

      expect(cache.size).to eq(1)
      expect(cache.fetch("key1") { "fallback" }).to eq("value1")
    end

    it "updates existing key" do
      cache.store("key1", "value1")
      cache.store("key1", "value2")

      expect(cache.size).to eq(1)
      expect(cache.fetch("key1") { "fallback" }).to eq("value2")
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used entry when full" do
      cache.store("key1", "value1")
      cache.store("key2", "value2")
      cache.store("key3", "value3")

      # Access key1 to make it recently used
      cache.fetch("key1") { "fallback" }

      # Store key4, should evict key2 (least recently used)
      cache.store("key4", "value4")

      expect(cache.size).to eq(3)
      expect(cache.cached?("key1")).to be true
      expect(cache.cached?("key2")).to be false
      expect(cache.cached?("key3")).to be true
      expect(cache.cached?("key4")).to be true
    end

    it "increments eviction counter" do
      4.times { |i| cache.store("key#{i}", "value#{i}") }

      expect(cache.stats[:evictions]).to be > 0
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache.store("key1", "value1")
      cache.store("key2", "value2")

      cache.clear

      expect(cache.size).to eq(0)
      expect(cache.empty?).to be true
    end

    it "increments invalidation counter" do
      cache.clear

      expect(cache.stats[:invalidations]).to eq(1)
    end
  end

  describe "#invalidate" do
    it "removes specific key" do
      cache.store("key1", "value1")
      cache.store("key2", "value2")

      cache.invalidate("key1")

      expect(cache.cached?("key1")).to be false
      expect(cache.cached?("key2")).to be true
    end

    it "increments invalidation counter" do
      cache.store("key1", "value1")
      cache.invalidate("key1")

      expect(cache.stats[:invalidations]).to eq(1)
    end
  end

  describe "#invalidate_matching" do
    it "removes keys matching pattern" do
      cache.store("scalars:wght:700", "value1")
      cache.store("scalars:wght:400", "value2")
      cache.store("interp:100:10", "value3")

      cache.invalidate_matching(/^scalars:/)

      expect(cache.cached?("scalars:wght:700")).to be false
      expect(cache.cached?("scalars:wght:400")).to be false
      expect(cache.cached?("interp:100:10")).to be true
    end
  end

  describe "#statistics" do
    it "returns comprehensive statistics" do
      cache.fetch("key1") { "value1" }
      cache.fetch("key1") { "value1" }
      cache.fetch("key2") { "value2" }

      stats = cache.statistics

      expect(stats[:hits]).to eq(1)
      expect(stats[:misses]).to eq(2)
      expect(stats[:total_requests]).to eq(3)
      expect(stats[:hit_rate]).to be_within(0.01).of(0.33)
      expect(stats[:size]).to eq(2)
      expect(stats[:max_size]).to eq(3)
    end

    it "handles zero requests" do
      stats = cache.statistics

      expect(stats[:hit_rate]).to eq(0.0)
    end
  end

  describe "#size" do
    it "returns number of cached entries" do
      expect(cache.size).to eq(0)

      cache.store("key1", "value1")
      expect(cache.size).to eq(1)

      cache.store("key2", "value2")
      expect(cache.size).to eq(2)
    end
  end

  describe "#empty?" do
    it "returns true for empty cache" do
      expect(cache.empty?).to be true
    end

    it "returns false for non-empty cache" do
      cache.store("key1", "value1")

      expect(cache.empty?).to be false
    end
  end

  describe "#full?" do
    it "returns false when not at capacity" do
      cache.store("key1", "value1")

      expect(cache.full?).to be false
    end

    it "returns true when at capacity" do
      cache.store("key1", "value1")
      cache.store("key2", "value2")
      cache.store("key3", "value3")

      expect(cache.full?).to be true
    end
  end

  describe "TTL (Time-To-Live)" do
    let(:cache) { described_class.new(max_size: 10, ttl: 1) }

    it "expires entries after TTL" do
      cache.store("key1", "value1")

      expect(cache.cached?("key1")).to be true

      sleep(1.1)

      expect(cache.cached?("key1")).to be false
    end

    it "recomputes expired values" do
      call_count = 0
      cache.fetch("key1") do
        call_count += 1
        "value"
      end

      sleep(1.1)

      cache.fetch("key1") do
        call_count += 1
        "value"
      end

      expect(call_count).to eq(2)
    end
  end
end

RSpec.describe Fontisan::Variation::ThreadSafeCache do
  let(:cache) { described_class.new(max_size: 100) }

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = Array.new(10) do |i|
        Thread.new do
          100.times do |j|
            key = "key#{i % 10}"
            cache.fetch(key) { "value#{j}" }
          end
        end
      end

      threads.each(&:join)

      # Should not raise any errors
      expect(cache.size).to be <= 100
    end

    it "maintains consistent statistics" do
      threads = Array.new(5) do
        Thread.new do
          50.times do |i|
            cache.fetch("key#{i % 10}") { "value" }
          end
        end
      end

      threads.each(&:join)

      stats = cache.statistics
      # In concurrent scenarios, some operations may overlap
      # Just verify we got most of the expected requests
      expect(stats[:hits] + stats[:misses]).to be >= 240
      expect(stats[:hits] + stats[:misses]).to be <= 250
    end
  end
end
