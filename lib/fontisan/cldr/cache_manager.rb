# frozen_string_literal: true

require "pathname"

module Fontisan
  module Cldr
    # Manages the on-disk CLDR cache layout.
    #
    # Cache root resolution honors `XDG_CONFIG_HOME` per the XDG Base
    # Directory Specification. Falls back to `~/.config` on Unix.
    #
    # Layout:
    #
    #   <root>/
    #     <version>/
    #       json/                 # extracted CLDR JSON archive
    #         cldr-json/
    #           cldr-characters-full/
    #             main/<lang>/characters.json
    #       index/
    #         languages.yml       # built index of per-language codepoint sets
    #
    # No network access — all methods are pure filesystem operations.
    module CacheManager
      LANGUAGES_INDEX_FILENAME = "languages.yml"
      private_constant :LANGUAGES_INDEX_FILENAME

      class << self
        # Root path of the CLDR cache.
        # @return [Pathname]
        def root
          base = xdg_config_home || File.join(Dir.home, ".config")
          Pathname.new(base).join("fontisan", "cldr")
        end

        # Per-version directory.
        # @param version [String] e.g. "46.0.0"
        # @return [Pathname]
        def version_dir(version)
          root.join(version)
        end

        # Directory where the raw CLDR JSON archive is extracted.
        # @param version [String]
        # @return [Pathname]
        def json_dir(version)
          version_dir(version).join("json")
        end

        # Directory containing the per-language characters.json files
        # inside the extracted archive.
        # @param version [String]
        # @return [Pathname]
        def characters_main_dir(version)
          json_dir(version).join("cldr-json", "cldr-characters-full", "main")
        end

        # Directory holding the derived language index for a version.
        # @param version [String]
        # @return [Pathname]
        def index_dir(version)
          version_dir(version).join("index")
        end

        def languages_index_path(version)
          index_dir(version).join(LANGUAGES_INDEX_FILENAME)
        end

        # True if the extracted JSON archive is present for this version.
        # @param version [String]
        # @return [Boolean]
        def cached?(version)
          characters_main_dir(version).exist?
        end

        # All versions currently in the cache (sorted ascending).
        # @return [Array<String>]
        def cached_versions
          return [] unless root.exist?

          root.children.select(&:directory?).map { |p| p.basename.to_s }.sort
        end

        # Create the version directory and json/index subdirs.
        # Idempotent.
        # @param version [String]
        def ensure_version_dir!(version)
          json_dir(version).mkpath
          index_dir(version).mkpath
        end

        # Remove a version from the cache. No-op if absent.
        # @param version [String]
        def remove_version(version)
          dir = version_dir(version)
          dir.rmtree if dir.exist?
        end

        private

        def xdg_config_home
          env = ENV["XDG_CONFIG_HOME"]
          return nil if env.nil? || env.empty?

          env
        end
      end
    end
  end
end
