# frozen_string_literal: true

# Adapts Octokit's API to the FixtureFonts::Downloader's "give me
# bytes for this URL" contract. Lives in its own file so the
# Downloader class stays focused on retry/routing logic and the
# URL-pattern dispatch lives separately.
#
# Octokit raises +Octokit::TooManyRequests+ or
# +Octokit::RateLimitExceeded+ on 429/403-rate-limit; the downloader's
# outer rescue catches +StandardError+ and retries.
module FixtureFonts
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
          fetch_via_get(client, url)
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
        unless asset
          raise Octokit::NotFound,
                "asset #{asset_name} not in #{repo_full}@#{tag}"
        end

        client.get(asset.url, accept: "application/octet-stream")
      end

      def fetch_via_get(client, url)
        client.get(url.to_s)
      end
    end
  end
end
