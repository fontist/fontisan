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
    # (5xx, connection reset, OpenTimeout, GitHub 429) doesn't sink a
    # fresh checkout. Permanent failures (404, 403) surface immediately.
    #
    # The downloader is a focused class, not a procedural Rakefile
    # patch, so the retry logic is unit-testable in isolation.
    #
    # == Authentication
    #
    # GitHub anonymous downloads are rate-limited to ~60 req/hour per IP.
    # CI runners share egress IPs, so parallel matrix jobs hit that
    # ceiling quickly and start receiving 429 Too Many Requests. To
    # avoid that, when the +GITHUB_TOKEN+ environment variable is set
    # (GitHub Actions auto-injects it for every workflow run), the
    # downloader sends it as a Bearer token. Authenticated requests get
    # 15,000 req/hour.
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

      # HTTP statuses worth retrying after a backoff. 5xx are
      # transient server errors; 429 is a transient rate-limit (always
      # retriable — server is explicitly telling the client to slow
      # down, not to go away permanently).
      RETRIABLE_HTTP_STATUSES = ((500..599).to_a + [429]).freeze

      # Status code returned when the client has been rate-limited.
      HTTP_TOO_MANY_REQUESTS = 429

      DEFAULT_MAX_RETRIES = 3
      DEFAULT_BASE_BACKOFF = 0.5 # seconds; doubles per attempt
      # Ceiling for the +Retry-After+ header value so a misbehaving
      # server can't stall CI for hours. 60s is well above GitHub's
      # typical 1-5s secondary-limit backoff.
      MAX_RETRY_AFTER_SECONDS = 60

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

      attr_reader :url, :destination, :max_retries, :base_backoff,
                  :sleep_method, :github_token

      # @param url [String] source URL.
      # @param destination [String] path to write bytes to. Parent dir
      #   is auto-created.
      # @param max_retries [Integer] total attempts including the
      #   first. 3 means: try, retry, retry.
      # @param base_backoff [Float] seconds to sleep before the first
      #   retry. Doubles per attempt (overridden by Retry-After on 429).
      # @param sleep_method [#call] injectable sleep (for tests).
      #   Defaults to Kernel.sleep.
      # @param github_token [String, nil] Bearer token for GitHub auth.
      #   Defaults to +ENV["GITHUB_TOKEN"]+ so CI auto-authenticates;
      #   pass +nil+ explicitly to force anonymous download in tests.
      def initialize(url:, destination:, max_retries: DEFAULT_MAX_RETRIES,
                     base_backoff: DEFAULT_BASE_BACKOFF,
                     sleep_method: method(:sleep),
                     github_token: ENV["GITHUB_TOKEN"])
        @url = url
        @destination = destination
        @max_retries = max_retries
        @base_backoff = base_backoff
        @sleep_method = sleep_method
        @github_token = github_token
      end

      # Performs the download. Returns the destination path on
      # success. Raises {Error} after exhausting retries.
      #
      # @return [String] destination path
      # @raise [Error]
      def call
        attempts = 0

        begin
          attempts += 1
          fetch_to_destination
          destination
        rescue StandardError => e
          raise if permanent_failure?(e)
          if attempts >= max_retries
            raise Error.new(url: url, attempts: attempts,
                            last_error: e)
          end

          sleep_method.call(backoff_seconds(e, attempts))
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
        #
        # Parsing with URI.parse first satisfies CodeQL's "open with
        # non-constant value" check: any string that isn't a valid URI
        # raises URI::InvalidURIError before OpenURI can dispatch on
        # it. The parsed URI's .open is OpenURI's standard entry.
        # rubocop:disable Security/Open
        URI.parse(url).open(open_uri_options) do |remote|
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
        options = {
          "User-Agent" => "fontisan-fixtures/1.0",
          redirect: true,
          open_timeout: 30,
          read_timeout: 120,
        }
        options["Authorization"] = "Bearer #{github_token}" if github_token
        options
      end

      def permanent_failure?(error)
        case error
        when OpenURI::HTTPError
          status = parse_http_status(error)
          status && !RETRIABLE_HTTP_STATUSES.include?(status)
        else
          RETRIABLE_ERRORS.none? { |klass| error.is_a?(klass) }
        end
      end

      # Seconds to wait before the next attempt. Honors the server's
      # +Retry-After+ header on 429 responses (capped); otherwise uses
      # exponential backoff from +base_backoff+.
      def backoff_seconds(error, attempts)
        retry_after = parse_retry_after(error)
        return retry_after if retry_after

        base_backoff * (2**(attempts - 1))
      end

      def parse_retry_after(error)
        return unless error.is_a?(OpenURI::HTTPError)
        return unless parse_http_status(error) == HTTP_TOO_MANY_REQUESTS

        header_value = error.io&.meta&.[]("retry-after")
        return unless header_value

        seconds = Integer(header_value, exception: false)
        return unless seconds&.positive?

        [seconds, MAX_RETRY_AFTER_SECONDS].min
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
