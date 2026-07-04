# frozen_string_literal: true

require "open-uri"
require "net/http"
require "fileutils"

module Fontisan
  # Tasks supporting the developer workflow: fixture downloads, etc.
  # Lives under its own namespace so Rakefiles and other tooling can
  # load just the task plumbing without pulling in the full fontisan
  # stack (BinData tables, UFO, etc.).
  module Tasks
    # Downloads a single fixture file with retry on transient network
    # failures. Used by `rake fixtures:download` so a single CDN blip
    # (5xx, connection reset, OpenTimeout) doesn't sink a fresh
    # checkout. Permanent failures (404, malformed URL) surface
    # immediately.
    #
    # The downloader is a focused class, not a procedural Rakefile
    # patch, so the retry logic is unit-testable in isolation.
    #
    # @example
    #   Fontisan::Tasks::FixtureDownloader.new(
    #     url: "https://github.com/.../font.ttf",
    #     destination: "spec/fixtures/font.ttf",
    #   ).call
    class FixtureDownloader
      RETRIABLE_ERRORS = [
        Net::OpenTimeout,
        Net::ReadTimeout,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::EHOSTUNREACH,
        Errno::ETIMEDOUT,
        EOFError,
        IOError,
      ].freeze

      # 5xx HTTP responses are transient server errors worth retrying.
      # 4xx are permanent (404, 403) and must fail fast.
      RETRIABLE_HTTP_STATUSES = (500..599)

      DEFAULT_MAX_RETRIES = 3
      DEFAULT_BASE_BACKOFF = 0.5 # seconds; doubles per attempt

      # Error raised after exhausting all retries. Carries the last
      # underlying exception so callers can log the root cause.
      class Error < StandardError
        attr_reader :last_error

        def initialize(url:, attempts:, last_error:)
          @last_error = last_error
          super("Failed to download #{url} after #{attempts} attempts: " \
                "#{last_error.class}: #{last_error.message}")
        end
      end

      attr_reader :url, :destination, :max_retries, :base_backoff, :sleep_method

      # @param url [String] source URL.
      # @param destination [String] path to write bytes to. Parent dir
      #   is auto-created.
      # @param max_retries [Integer] total attempts including the
      #   first. 3 means: try, retry, retry.
      # @param base_backoff [Float] seconds to sleep before the first
      #   retry. Doubles per attempt.
      # @param sleep_method [#call] injectable sleep (for tests).
      #   Defaults to Kernel.sleep.
      def initialize(url:, destination:, max_retries: DEFAULT_MAX_RETRIES,
                     base_backoff: DEFAULT_BASE_BACKOFF, sleep_method: method(:sleep))
        @url = url
        @destination = destination
        @max_retries = max_retries
        @base_backoff = base_backoff
        @sleep_method = sleep_method
      end

      # Performs the download. Returns the destination path on
      # success. Raises {Error} after exhausting retries.
      #
      # @return [String] destination path
      # @raise [Error]
      def call
        attempts = 0
        nil

        begin
          attempts += 1
          fetch_to_destination
          destination
        rescue StandardError => e
          e
          raise if permanent_failure?(e)
          raise Error.new(url: url, attempts: attempts, last_error: e) if attempts >= max_retries

          backoff = base_backoff * (2**(attempts - 1))
          sleep_method.call(backoff)
          retry
        end
      end

      private

      def fetch_to_destination
        FileUtils.mkdir_p(File.dirname(destination))

        # IO.copy_stream avoids loading the whole response into memory
        # and is more Windows-compatible than remote.read + File.binwrite.
        # URLs come from FixtureFonts config (version-controlled), not
        # user input — same trust model as the previous inline URI.open
        # call in the Rakefile.
        # rubocop:disable Security/Open
        URI.open(url, open_uri_options) do |remote|
          File.open(destination, "wb") do |file|
            IO.copy_stream(remote, file)
          end
        end
        # rubocop:enable Security/Open
      end

      # `open-uri` follows redirects by default and surfaces HTTP
      # errors as `OpenURI::HTTPError` whose `io.status` is the `[code,
      # message]` array. We re-raise non-retriable 4xx as
      # `permanent-failure`-tagged exceptions so the retry loop exits.
      def open_uri_options
        {
          "User-Agent" => "fontisan-fixtures/1.0",
          redirect: true,
          open_timeout: 30,
          read_timeout: 120,
        }
      end

      def permanent_failure?(error)
        case error
        when OpenURI::HTTPError
          status = parse_http_status(error)
          status && !RETRIABLE_HTTP_STATUSES.cover?(status)
        else
          RETRIABLE_ERRORS.none? { |klass| error.is_a?(klass) }
        end
      end

      def parse_http_status(error)
        io = error.io
        return nil unless io

        status = io.status
        return nil unless status

        status.first.to_i
      rescue StandardError
        nil
      end
    end
  end
end
