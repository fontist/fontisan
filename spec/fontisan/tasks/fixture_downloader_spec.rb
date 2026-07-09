# frozen_string_literal: true

require "spec_helper"
require "fontisan/tasks"
require "tmpdir"
require "stringio"
require "open-uri"

# Lightweight stand-in for the Net::HTTP response object that
# OpenURI::HTTPError wraps. OpenURI needs .status -> [code, message]
# and our retry-after parser reads .meta["retry-after"]; a Struct
# satisfies both without doubles.
HttpStatusIo = Struct.new(:status, :meta)

RSpec.describe Fontisan::Tasks::FixtureDownloader do
  let(:destination) { File.join(Dir.tmpdir, "fontisan-spec-#{Process.pid}-#{rand(10_000)}.dat") }
  let(:sleeps) { [] }
  let(:sleep_method) { ->(seconds) { sleeps << seconds } }
  # Real URI instance used as the stub target. Stubbing .open on a
  # real instance is not a "double" — the object is genuine, only
  # its .open behavior is virtualized for the test.
  let(:parsed_uri) { URI.parse("https://example.com/font.ttf") }

  before do
    allow(URI).to receive(:parse).and_return(parsed_uri)
  end

  after do
    File.delete(destination) if File.exist?(destination)
  end

  def http_error(code, message, meta: {})
    OpenURI::HTTPError.new("#{code} #{message}",
                           HttpStatusIo.new([code.to_s, message], meta))
  end

  describe "#call" do
    it "writes the response body to the destination on first try" do
      allow(parsed_uri).to receive(:open).and_yield(StringIO.new("hello world"))

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
      )

      expect(downloader.call).to eq(destination)
      expect(File.read(destination)).to eq("hello world")
    end

    it "creates parent directories as needed" do
      nested_dir = File.join(Dir.tmpdir, "fontisan-spec-#{rand(10_000)}")
      nested = File.join(nested_dir, "nested", "font.dat")
      allow(parsed_uri).to receive(:open).and_yield(StringIO.new("x"))

      downloader = described_class.new(
        url: "https://example.com/font.dat",
        destination: nested,
        sleep_method: sleep_method,
      )

      begin
        downloader.call
        expect(File.exist?(nested)).to be true
      ensure
        FileUtils.rm_rf(nested_dir)
      end
    end

    it "retries on transient errors and succeeds on a later attempt" do
      attempts = 0
      responses = [
        proc { raise Errno::ECONNRESET.new },
        proc { raise Net::OpenTimeout.new },
        proc { |&block| block.call(StringIO.new("late success")) },
      ]
      allow(parsed_uri).to receive(:open) do |_opts, &block|
        responses[(attempts += 1) - 1].call(&block)
      end

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 3,
        base_backoff: 0.001,
        sleep_method: sleep_method,
      )

      expect(downloader.call).to eq(destination)
      expect(File.read(destination)).to eq("late success")
      expect(sleeps.length).to eq(2)
    end

    it "raises Error after exhausting retries" do
      allow(parsed_uri).to receive(:open).and_raise(Errno::ECONNRESET.new)

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 3,
        base_backoff: 0.001,
        sleep_method: sleep_method,
      )

      expect { downloader.call }.to raise_error(described_class::Error) do |err|
        expect(err.last_error).to be_a(Errno::ECONNRESET)
        expect(err.message).to include("3 attempts")
        expect(err.message).to include("ECONNRESET")
      end
      expect(sleeps.length).to eq(2)
    end

    it "uses exponential backoff between retries" do
      allow(parsed_uri).to receive(:open).and_raise(Errno::ECONNRESET.new)

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 4,
        base_backoff: 1.0,
        sleep_method: sleep_method,
      )

      expect { downloader.call }.to raise_error(described_class::Error)
      # 3 sleeps for 4 attempts: base * 2**0, base * 2**1, base * 2**2
      expect(sleeps).to eq([1.0, 2.0, 4.0])
    end

    it "fails fast on 4xx without retrying (except 429)" do
      allow(parsed_uri).to receive(:open).and_raise(http_error(404, "Not Found"))

      downloader = described_class.new(
        url: "https://example.com/missing.ttf",
        destination: destination,
        max_retries: 5,
        sleep_method: sleep_method,
      )

      expect { downloader.call }.to raise_error(OpenURI::HTTPError)
      expect(sleeps.length).to eq(0)
    end

    it "retries on 5xx HTTP errors" do
      attempts = 0
      responses = [
        proc { raise http_error(503, "Service Unavailable") },
        proc { raise http_error(502, "Bad Gateway") },
        proc { |&block| block.call(StringIO.new("after 5xx recovery")) },
      ]
      allow(parsed_uri).to receive(:open) do |_opts, &block|
        responses[(attempts += 1) - 1].call(&block)
      end

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 3,
        base_backoff: 0.001,
        sleep_method: sleep_method,
      )

      expect(downloader.call).to eq(destination)
      expect(File.read(destination)).to eq("after 5xx recovery")
      expect(attempts).to eq(3)
    end

    it "retries on 429 Too Many Requests (treated as transient)" do
      attempts = 0
      responses = [
        proc { raise http_error(429, "Too Many Requests") },
        proc { |&block| block.call(StringIO.new("after rate limit")) },
      ]
      allow(parsed_uri).to receive(:open) do |_opts, &block|
        responses[(attempts += 1) - 1].call(&block)
      end

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 3,
        base_backoff: 0.001,
        sleep_method: sleep_method,
      )

      expect(downloader.call).to eq(destination)
      expect(File.read(destination)).to eq("after rate limit")
      expect(attempts).to eq(2)
    end

    it "honors the Retry-After header on 429 instead of exponential backoff" do
      attempts = 0
      allow(parsed_uri).to receive(:open) do |_opts, &block|
        attempts += 1
        if attempts == 1
          raise http_error(429, "Too Many Requests",
                           meta: { "retry-after" => "7" })
        else
          block.call(StringIO.new("after retry-after"))
        end
      end

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 3,
        base_backoff: 1.0, # would normally sleep 1.0 — Retry-After overrides
        sleep_method: sleep_method,
        github_token: nil,
      )

      expect(downloader.call).to eq(destination)
      expect(sleeps).to eq([7])
    end

    it "caps Retry-After at MAX_RETRY_AFTER_SECONDS" do
      attempts = 0
      allow(parsed_uri).to receive(:open) do |_opts, &block|
        attempts += 1
        if attempts == 1
          raise http_error(429, "Too Many Requests",
                           meta: { "retry-after" => "3600" })
        else
          block.call(StringIO.new("after cap"))
        end
      end

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 3,
        base_backoff: 0.001,
        sleep_method: sleep_method,
      )

      expect(downloader.call).to eq(destination)
      expect(sleeps).to eq([described_class::MAX_RETRY_AFTER_SECONDS])
    end

    it "falls back to exponential backoff when Retry-After is missing" do
      allow(parsed_uri).to receive(:open).and_raise(
        http_error(429, "Too Many Requests"),
      )

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        max_retries: 2,
        base_backoff: 2.0,
        sleep_method: sleep_method,
      )

      expect { downloader.call }.to raise_error(described_class::Error)
      # First retry sleeps base * 2**0 = 2.0; no Retry-After present.
      expect(sleeps).to eq([2.0])
    end

    it "sends a User-Agent header identifying the downloader" do
      captured_options = nil
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: nil,
      ).call

      expect(captured_options["User-Agent"]).to start_with("fontisan-fixtures/")
    end

    it "sends Bearer Authorization when github_token is provided" do
      captured_options = nil
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      described_class.new(
        url: "https://github.com/owner/repo/raw/main/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token_123",
      ).call

      expect(captured_options["Authorization"]).to eq("Bearer ghs_test_token_123")
    end

    it "omits Authorization when github_token is nil" do
      captured_options = nil
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: nil,
      ).call

      expect(captured_options).not_to have_key("Authorization")
    end

    it "defaults github_token from ENV['GITHUB_TOKEN']" do
      captured_options = nil
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      previous = ENV["GITHUB_TOKEN"]
      ENV["GITHUB_TOKEN"] = "env_token_abc"
      begin
        described_class.new(
          url: "https://github.com/owner/repo/raw/main/font.ttf",
          destination: destination,
          sleep_method: sleep_method,
        ).call
      ensure
        ENV["GITHUB_TOKEN"] = previous
      end

      expect(captured_options["Authorization"]).to eq("Bearer env_token_abc")
    end
  end

  describe described_class::Error do
    it "exposes the underlying exception via #last_error" do
      underlying = Errno::ECONNRESET.new
      err = described_class.new(url: "u", attempts: 3, last_error: underlying)

      expect(err.last_error).to equal(underlying)
      expect(err.message).to include("u")
      expect(err.message).to include("3 attempts")
    end
  end
end
