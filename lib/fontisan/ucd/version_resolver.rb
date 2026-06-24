# frozen_string_literal: true

require "net/http"
require "uri"
require "rubygems"

module Fontisan
  module Ucd
    # Resolves a user-supplied version intent to a concrete version string.
    #
    # Three input modes:
    #
    #   resolve(nil)           # default_version from config
    #   resolve(:default)      # default_version from config
    #   resolve("17.0.0")      # explicit; validated against known_versions
    #   resolve(:latest)       # probes listing_url, picks highest; falls
    #                          # back to default on failure
    #
    module VersionResolver
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
                "UCD version #{version.inspect} is not recognized. " \
                "Known versions: #{Config.known_versions.join(', ')}"
        end

        private

        # Best-effort scrape of the unicode.org ucdxml directory listing.
        # Returns the highest semver found, or Config.default_version on
        # any failure.
        def probe_latest
          versions = fetch_directory_versions
          return fallback_latest("directory listing was empty") if versions.empty?

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
          warn "Ucd::VersionResolver: --latest probe failed (#{reason}); " \
               "falling back to default #{Config.default_version.inspect}"
          Config.default_version
        end

        def fetch_directory_versions
          uri = URI(Config.listing_url)
          html = Net::HTTP.get(uri)
          html.scan(%r{href="(\d+\.\d+\.\d+)/?"}i).flatten.uniq
        end
      end
    end
  end
end
