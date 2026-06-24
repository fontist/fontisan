# frozen_string_literal: true

require "yaml"

module Fontisan
  module Cldr
    # Single source of truth for CLDR version selection.
    #
    # Wraps `lib/fontisan/config/cldr.yml`. Loads the YAML once at first
    # access and memoizes. All other Cldr::* classes resolve versions,
    # URLs, and known-version validation through this module.
    module Config
      CONFIG_PATH = File.expand_path("../config/cldr.yml", __dir__)
      private_constant :CONFIG_PATH

      class << self
        # The CLDR version Fontisan uses by default for auto-download and
        # `fontisan cldr download` (no args). String like "46.0.0".
        def default_version
          data[:default_version]
        end

        # Array of CLDR version strings this Fontisan release recognizes.
        # Used by VersionResolver to reject unknown versions early.
        def known_versions
          data[:known_versions]
        end

        # Base URL for fetching CLDR JSON artifacts.
        def base_url
          data[:base_url]
        end

        # Listing URL for `--latest` probing.
        def listing_url
          data[:listing_url]
        end

        # Full URL to the CLDR JSON full archive for a version.
        # @param version [String] e.g. "46.0.0"
        # @return [String]
        def archive_url_for(version)
          "#{base_url}/#{version}/cldr-#{version}-json-full.zip"
        end

        # True if the version appears in `known_versions`.
        def known?(version)
          known_versions.include?(version)
        end

        private

        def data
          @data ||= YAML.load_file(CONFIG_PATH).transform_keys(&:to_sym)
        end
      end
    end
  end
end
