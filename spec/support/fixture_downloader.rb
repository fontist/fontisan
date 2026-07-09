# frozen_string_literal: true

require "open-uri"
require "net/http"
require "fileutils"

# Test-fixture downloader used by `rake fixtures:download`. Lives under
# spec/support (not lib/) because it is purely test infrastructure:
# fontisan-the-gem never downloads fonts at runtime. Moving it out of
# lib/ keeps the published gem clean of any download code paths and
# lets the downloader take dependencies (Octokit) that belong in the
# Gemfile, not the gemspec.
#
# == GitHub authentication
#
# GitHub anonymous downloads are rate-limited to ~60 req/hour per IP.
# CI runners share egress IPs, so parallel matrix jobs hit that ceiling
# quickly and start receiving 429 Too Many Requests. Two-part fix:
#
# 1. When +ENV["GITHUB_TOKEN"]+ is set (GitHub Actions auto-injects it
#    for every workflow run) AND the +octokit+ gem is available, the
#    downloader uses Octokit for GitHub URLs. Octokit authenticates
#    every request, auto-handles rate-limit resets, and addresses the
#    raw-content endpoints directly — no github.com →
#    raw.githubusercontent.com redirect that would strip the
#    Authorization header.
# 2. Otherwise, the downloader falls back to open-uri with a Bearer
#    Authorization header scoped to known GitHub hosts. This still
#    hits the rate limit on redirects but retries 429 with backoff
#    and Retry-After honoring.
#
# Octokit is a Gemfile-only dependency (group: :test); it is NOT in
# fontisan.gemspec. Production installs never pull it in.
module FixtureFonts
  # Downloads a single fixture file with retry on transient network
  # failures. Used by `rake fixtures:download` so a single CDN blip
  # (5xx, connection reset, OpenTimeout, GitHub 429) doesn't sink a
  # fresh checkout. Permanent failures (404, malformed URL) surface
  # immediately.
  class Downloader
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

    # HTTP statuses worth retrying after a backoff. 5xx are transient
    # server errors; 429 is a transient rate-limit (always retriable —
    # server is explicitly telling the client to slow down, not to go
    # away permanently).
    RETRIABLE_HTTP_STATUSES = ((500..599).to_a + [429]).freeze

    # Status code returned when the client has been rate-limited.
    HTTP_TOO_MANY_REQUESTS = 429

    DEFAULT_MAX_RETRIES = 3
    DEFAULT_BASE_BACKOFF = 0.5 # seconds; doubles per attempt
    # Ceiling for the +Retry-After+ header value so a misbehaving
    # server can't stall CI for hours. 60s is well above GitHub's
    # typical 1-5s secondary-limit backoff.
    MAX_RETRY_AFTER_SECONDS = 60

    # Hosts that legitimately accept the GITHUB_TOKEN as Bearer auth.
    # Anything else (raw.githubusercontent.com subdomain variants,
    # third-party CDNs, mirror sites) is treated as untrusted. Used
    # by +send_auth?+ as the credential-leak guard.
    GITHUB_HOSTS = %w[
      github.com
      codeload.github.com
      objects.githubusercontent.com
      api.github.com
      raw.githubusercontent.com
    ].freeze

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

    # Performs the download. Returns the destination path on success.
    # Raises {Error} after exhausting retries.
    #
    # Routes GitHub URLs to Octokit when both GITHUB_TOKEN and the
    # +octokit+ gem are available; otherwise falls back to open-uri.
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

    # True when this download should use Octokit instead of open-uri:
    # GitHub host, token present, Octokit gem loadable. Memoized so
    # the +require+ attempt happens once per downloader instance.
    def use_octokit?(parsed)
      github_host?(parsed) && github_token && octokit_loaded?
    end

    def octokit_loaded?
      return @octokit_loaded if defined?(@octokit_loaded)

      @octokit_loaded = begin
        require "octokit"
        true
      rescue LoadError
        false
      end
    end

    def github_host?(parsed)
      GITHUB_HOSTS.include?(parsed.host.to_s)
    end

    def fetch_to_destination
      FileUtils.mkdir_p(File.dirname(destination))
      parsed = URI.parse(url)

      if use_octokit?(parsed)
        fetch_via_octokit(parsed)
      else
        warn_github_octokit_missing_once(parsed)
        fetch_via_open_uri(parsed)
      end
    end

    # One-time-per-process informational message when the downloader
    # takes the open-uri fallback for a GitHub URL. Surfaces the
    # silent-degradation gap (open-uri loses the Authorization header
    # on github.com -> raw.githubusercontent.com redirects, so the
    # rate-limit fix from PR #109 only helps via retry, not via
    # auth lift). Actionable: tells the user to run `bundle install`.
    #
    # Only fires when a GitHub URL + token are present but Octokit
    # isn't loaded — the exact scenario where the user would benefit.
    # Silent in the normal path (Octokit loaded, or non-GitHub URL,
    # or anonymous download).
    def warn_github_octokit_missing_once(parsed)
      return unless github_token
      return unless github_host?(parsed)
      return if @octokit_warning_emitted

      @octokit_warning_emitted = true
      warn "[fixtures:download] Octokit not loaded; GitHub URLs fall back to " \
           "open-uri (rate-limit-prone on redirects). Run `bundle install` " \
           "to enable authenticated downloads via Octokit."
    end

    # Octokit handles auth, rate-limit resets, and addresses the right
    # endpoint per URL shape (release asset, raw file, API blob) — no
    # github.com → raw.githubusercontent.com redirect to strip the
    # Authorization header.
    def fetch_via_octokit(parsed)
      bytes = OctokitFetcher.bytes(url: parsed, token: github_token)
      File.binwrite(destination, bytes)
    end

    def fetch_via_open_uri(parsed)
      # open-uri follows redirects by default and surfaces HTTP
      # errors as +OpenURI::HTTPError+ whose +io.status+ is the
      # +[code, message]+ array. The Authorization header is gated
      # on +send_auth?+ so a token captured from ENV never leaks to
      # a non-GitHub host.
      #
      # rubocop:disable Security/Open
      parsed.open(open_uri_options(parsed)) do |remote|
        File.open(destination, "wb") do |file|
          IO.copy_stream(remote, file)
        end
      end
      # rubocop:enable Security/Open
    end

    def open_uri_options(parsed)
      options = {
        "User-Agent" => "fontisan-fixtures/1.0",
        redirect: true,
        open_timeout: 30,
        read_timeout: 120,
      }
      options["Authorization"] = "Bearer #{github_token}" if send_auth?(parsed)
      options
    end

    # True only when +github_token+ is configured AND the URL targets
    # a GitHub-owned host. The host check is the credential-leak
    # guard: an attacker who controls a different host can't trick
    # the downloader into forwarding the CI token.
    def send_auth?(parsed)
      return false unless github_token

      github_host?(parsed)
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

  # Adapts Octokit's API to the downloader's "give me bytes for this
  # URL" contract. Extracted as a sibling so +Downloader+ stays
  # focused on retry/routing logic and the URL-pattern dispatch
  # lives separately.
  #
  # Octokit raises +Octokit::TooManyRequests+ or +Octokit::RateLimitExceeded+
  # on 429/403-rate-limit; the downloader's outer rescue catches
  # +StandardError+ and retries.
  module OctokitFetcher
    class << self
      # @param url [URI] GitHub URL to fetch.
      # @param token [String] GITHUB_TOKEN for auth.
      # @return [String] raw bytes of the response body.
      def bytes(url:, token:)
        client = Octokit::Client.new(access_token: token, auto_paginate: true)

        case url.host
        when "github.com"
          fetch_from_github_com(client, url)
        when "raw.githubusercontent.com"
          fetch_from_raw(client, url)
        when "codeload.github.com"
          fetch_via_get(client, url)
        when "api.github.com", "objects.githubusercontent.com"
          fetch_via_get(client, url)
        else
          fetch_via_get(client, url)
        end
      end

      private

      # github.com URLs come in several shapes. Dispatch by path:
      #   /owner/repo/raw/<ref>/<path>    → Octokit.contents (≤1MB)
      #                                   → raw.githubusercontent fallback
      #   /owner/repo/releases/download/<tag>/<asset>
      #                                    → release asset API
      #   everything else                  → authenticated GET
      def fetch_from_github_com(client, url)
        if (m = url.path.match(%r{\A/(.+)/(.+)/raw/(.+)\z}))
          owner_repo_raw(client, m[1], m[2], m[3])
        elsif (m = url.path.match(%r{\A/(.+)/(.+)/releases/download/(.+)/(.+)\z}))
          release_asset(client, m[1], m[2], m[3], m[4])
        else
          fetch_via_get(client, url)
        end
      end

      # raw.githubusercontent.com is the redirect target of
      # github.com/.../raw/... and accepts the token directly.
      def fetch_from_raw(client, url)
        fetch_via_get(client, url)
      end

      # /owner/repo/raw/<ref>/<path...>
      # Octokit.contents caps at 1MB. For larger files, talk to
      # raw.githubusercontent.com directly with the same auth —
      # Octokit::Client#get preserves the Authorization header on
      # the request it actually makes.
      def owner_repo_raw(client, owner, repo, ref_and_path)
        ref, *path_parts = ref_and_path.split("/", 2)
        path = path_parts.first
        repo_full = "#{owner}/#{repo}"
        begin
          item = client.contents(repo_full, path: path, ref: ref)
          return Base64.decode64(item.content) if item&.content && item.content != ""
        rescue Octokit::NotFound
          # fall through to raw fetch
        end
        raw_url = URI::HTTPS.build(host: "raw.githubusercontent.com",
                                   path: "/#{repo_full}/#{ref}/#{path}")
        fetch_via_get(client, raw_url)
      end

      def release_asset(client, owner, repo, tag, asset_name)
        repo_full = "#{owner}/#{repo}"
        release = client.release_by_tag(repo_full, tag)
        asset = release.rels[:assets].get.find { |a| a.name == asset_name }
        raise Octokit::NotFound, "asset #{asset_name} not in #{repo_full}@#{tag}" unless asset

        client.get(asset.url, accept: "application/octet-stream")
      end

      def fetch_via_get(client, url)
        client.get(url.to_s)
      end
    end
  end
end
