# frozen_string_literal: true

require "spec_helper"
require "fontisan/tasks"
require "tmpdir"
require "stringio"
require "open-uri"

# Lightweight stand-in for the Net::HTTP response object that
# OpenURI::HTTPError wraps. OpenURI only needs .status -> [code,
# message]; a Struct satisfies that without doubles, and behaves
# identically when our code reads it.
HttpStatusIo = Struct.new(:status)

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

  def http_error(code, message)
    OpenURI::HTTPError.new("#{code} #{message}", HttpStatusIo.new([code.to_s, message]))
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

    it "fails fast on 4xx without retrying" do
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
      ).call

      expect(captured_options["User-Agent"]).to start_with("fontisan-fixtures/")
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
