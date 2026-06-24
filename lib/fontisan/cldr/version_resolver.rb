# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "rubygems"

module Fontisan
  module Cldr
    # Resolves a user-supplied version intent to a concrete CLDR version.
    #
    # Mirrors {Ucd::VersionResolver}. Three input modes:
    #
    #   resolve(nil)           # default_version from config
    #   resolve(:default)      # default_version from config
    #   resolve("46.0.0")      # explicit; validated against known_versions
    #   resolve(:latest)       # probes GitHub releases, picks highest;
    #                          # falls back to default on failure
    module VersionResolver
      GITHUB_RELEASE_TAG = %r{ref/tags/(\d+(?:\.\d+)+)}
      private_constant :GITHUB_RELEASE_TAG

      class << self
        # @param intent [nil, :default, :latest, String]
        # @return [String] a concrete version string
        def resolve(intent)
          case intent
          when nil, :default
            Config.default_version
          when :latest
            probe_latest
          else
            validate!(intent)
            intent
          end
        end

        # Raise UnknownVersionError unless `version` is in known_versions.
        # @param version [String]
        # @return [void]
        def validate!(version)
          return if Config.known?(version)

          raise UnknownVersionError,
                "CLDR version #{version.inspect} is not recognized. " \
                "Known versions: #{Config.known_versions.join(', ')}"
        end

        private

        # Best-effort probe of the GitHub releases API for cldr-json.
        # Returns the highest semver found among tagged releases, or
        # Config.default_version on any failure.
        def probe_latest
          versions = fetch_release_versions
          return fallback_latest("releases listing was empty") if versions.empty?

          highest = versions.max_by { |v| Gem::Version.new(v) }
          if Config.known?(highest)
            highest
          else
            fallback_latest("#{highest.inspect} is not in known_versions; using default")
          end
        rescue StandardError => e
          fallback_latest(e.message)
        end

        def fallback_latest(reason)
          warn "Cldr::VersionResolver: --latest probe failed (#{reason}); " \
               "falling back to default #{Config.default_version.inspect}"
          Config.default_version
        end

        def fetch_release_versions
          uri = URI(Config.listing_url)
          response = Net::HTTP.get_response(uri)
          return [] unless response.is_a?(Net::HTTPSuccess)

          releases = JSON.parse(response.body || "[]")
          releases.filter_map do |release|
            tag = release["tag_name"]
            next unless tag

            match = tag.match(/\A(\d+(?:\.\d+)+)\z/)
            match && match[1]
          end
        end
      end
    end
  end
end
