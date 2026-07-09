# frozen_string_literal: true

require "spec_helper"
require_relative "fixture_downloader"
require "tmpdir"
require "stringio"
require "open-uri"

# Lightweight stand-in for the Net::HTTP response object that
# OpenURI::HTTPError wraps. OpenURI needs .status -> [code, message]
# and our retry-after parser reads .meta["retry-after"]; a Struct
# satisfies both without doubles.
HttpStatusIo = Struct.new(:status, :meta)

RSpec.describe FixtureFonts::Downloader do
  let(:destination) { File.join(Dir.tmpdir, "fontisan-spec-#{Process.pid}-#{rand(10_000)}.dat") }
  let(:sleeps) { [] }
  let(:sleep_method) { ->(seconds) { sleeps << seconds } }
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

  # Helper: stub a downloader so it always uses the open-uri path
  # regardless of whether Octokit is actually installed. Lets the
  # open-uri-specific tests run on dev machines where Octokit is
  # loaded via the Gemfile.
  def force_open_uri_path(downloader)
    allow(downloader).to receive(:octokit_loaded?).and_return(false)
  end

  describe "#call" do
    it "writes the response body to the destination on first try" do
      allow(parsed_uri).to receive(:open).and_yield(StringIO.new("hello world"))

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
      )
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

      expect { downloader.call }.to raise_error(described_class::Error)
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
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

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
        base_backoff: 1.0,
        sleep_method: sleep_method,
        github_token: nil,
      )
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

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
      force_open_uri_path(downloader)

      expect { downloader.call }.to raise_error(described_class::Error)
      expect(sleeps).to eq([2.0])
    end

    it "sends a User-Agent header identifying the downloader" do
      captured_options = nil
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: nil,
      )
      force_open_uri_path(downloader)
      downloader.call

      expect(captured_options["User-Agent"]).to start_with("fontisan-fixtures/")
    end

    it "sends Bearer Authorization when github_token is set and URL is GitHub" do
      captured_options = nil
      parsed_uri.host = "github.com"
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      begin
        downloader = described_class.new(
          url: "https://github.com/owner/repo/raw/main/font.ttf",
          destination: destination,
          sleep_method: sleep_method,
          github_token: "ghs_test_token_123",
        )
        force_open_uri_path(downloader)
        downloader.call
      ensure
        parsed_uri.host = "example.com"
      end

      expect(captured_options["Authorization"]).to eq("Bearer ghs_test_token_123")
    end

    it "withholds Authorization from non-GitHub hosts even when token is set" do
      captured_options = nil
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      downloader = described_class.new(
        url: "https://evil.example.com/steal",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token_123",
      )
      force_open_uri_path(downloader)
      downloader.call

      expect(captured_options).not_to have_key("Authorization")
    end

    it "defaults github_token from ENV['GITHUB_TOKEN']" do
      captured_options = nil
      parsed_uri.host = "github.com"
      allow(parsed_uri).to receive(:open) do |options|
        captured_options = options
        StringIO.new("ok")
      end

      previous = ENV["GITHUB_TOKEN"]
      ENV["GITHUB_TOKEN"] = "env_token_abc"
      begin
        downloader = described_class.new(
          url: "https://github.com/owner/repo/raw/main/font.ttf",
          destination: destination,
          sleep_method: sleep_method,
        )
        force_open_uri_path(downloader)
        downloader.call
      ensure
        ENV["GITHUB_TOKEN"] = previous
        parsed_uri.host = "example.com"
      end

      expect(captured_options["Authorization"]).to eq("Bearer env_token_abc")
    end
  end

  describe "Octokit routing" do
    # The Octokit path is taken only when ALL THREE of: GitHub host,
    # token present, Octokit gem loadable. Tests stub octokit_loaded?
    # to force each path explicitly so the suite passes whether or
    # not Octokit is installed in the dev environment.
    #
    # github_uri is built via URI::HTTPS.build (not URI.parse) so the
    # outer before-block URI.parse stub doesn't contaminate it.
    let(:github_uri) do
      URI::HTTPS.build(host: "github.com",
                       path: "/owner/repo/raw/main/font.ttf")
    end

    it "routes GitHub URLs through OctokitFetcher when token + Octokit present" do
      downloader = described_class.new(
        url: "https://github.com/owner/repo/raw/main/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token",
      )
      allow(URI).to receive(:parse).and_return(github_uri)
      allow(downloader).to receive(:octokit_loaded?).and_return(true)
      expect(FixtureFonts::OctokitFetcher).to receive(:bytes)
        .with(url: github_uri, token: "ghs_test_token")
        .and_return("fetched-via-octokit")

      downloader.call

      expect(File.read(destination)).to eq("fetched-via-octokit")
    end

    it "falls back to open-uri when Octokit gem is not installed" do
      # Even with a GitHub URL + token, missing Octokit means the
      # open-uri path runs (with Authorization header, subject to its
      # redirect-stripping limitation).
      downloader = described_class.new(
        url: "https://github.com/owner/repo/raw/main/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token",
      )
      allow(URI).to receive(:parse).and_return(github_uri)
      allow(downloader).to receive(:octokit_loaded?).and_return(false)
      allow(github_uri).to receive(:open) do |options, &block|
        expect(options["Authorization"]).to eq("Bearer ghs_test_token")
        block.call(StringIO.new("via-open-uri"))
      end

      downloader.call

      expect(File.read(destination)).to eq("via-open-uri")
    end

    it "does not route non-GitHub URLs through Octokit even when available" do
      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token",
      )
      allow(URI).to receive(:parse).and_return(parsed_uri)
      allow(downloader).to receive(:octokit_loaded?).and_return(true)
      expect(FixtureFonts::OctokitFetcher).not_to receive(:bytes)
      allow(parsed_uri).to receive(:open).and_yield(StringIO.new("via-open-uri"))

      downloader.call

      expect(File.read(destination)).to eq("via-open-uri")
    end

    it "warns once when falling back to open-uri for a GitHub URL (Octokit missing)" do
      # The silent-degradation gap: open-uri loses the Authorization
      # header on github.com → raw.githubusercontent.com redirects.
      # When the downloader takes that path for a GitHub URL + token,
      # it emits ONE informational warning per process so the user
      # knows their downloads are rate-limit-prone and how to fix it.
      downloader = described_class.new(
        url: "https://github.com/owner/repo/raw/main/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token",
      )
      allow(URI).to receive(:parse).and_return(github_uri)
      allow(downloader).to receive(:octokit_loaded?).and_return(false)
      allow(github_uri).to receive(:open) do |_, &block|
        block.call(StringIO.new("via-open-uri"))
      end

      expect { downloader.call }.to output(
        /Octokit not loaded.*bundle install/,
      ).to_stderr

      # Second call: no repeated warning (one-time-per-process).
      expect { downloader.call }.not_to output(/Octokit not loaded/).to_stderr
    end

    it "stays silent for non-GitHub URLs even when Octokit is missing" do
      downloader = described_class.new(
        url: "https://example.com/font.ttf",
        destination: destination,
        sleep_method: sleep_method,
        github_token: "ghs_test_token",
      )
      allow(parsed_uri).to receive(:open) do |_, &block|
        block.call(StringIO.new("ok"))
      end

      expect { downloader.call }.not_to output.to_stderr
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
