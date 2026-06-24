# frozen_string_literal: true

require "pathname"

module Fontisan
  module Ucd
    # Manages the on-disk UCD cache layout.
    #
    # Cache root resolution honors `XDG_CONFIG_HOME` per the XDG Base
    # Directory Specification. Falls back to `~/.config` on Unix and
    # `~/.config` (literal) elsewhere — consistent with other Fontisan
    # config paths.
    #
    # Layout:
    #
    #   <root>/
    #     <version>/
    #       ucdxml/
    #         ucd.all.flat.xml
    #       index/
    #         blocks.yml
    #         scripts.yml
    #
    # No network access — all methods are pure filesystem operations.
    module CacheManager
      UCDXML_FILENAME = "ucd.all.flat.xml"
      private_constant :UCDXML_FILENAME

      BLOCKS_INDEX_FILENAME = "blocks.yml"
      SCRIPTS_INDEX_FILENAME = "scripts.yml"
      private_constant :BLOCKS_INDEX_FILENAME, :SCRIPTS_INDEX_FILENAME

      class << self
        # Root path of the UCD cache.
        # @return [Pathname]
        def root
          base = xdg_config_home || File.join(Dir.home, ".config")
          Pathname.new(base).join("fontisan", "unicode")
        end

        # Per-version directory.
        # @param version [String] e.g. "17.0.0"
        # @return [Pathname]
        def version_dir(version)
          root.join(version)
        end

        # Path to the unpacked UCDXML flat file for a version.
        # @param version [String]
        # @return [Pathname]
        def ucdxml_path(version)
          version_dir(version).join("ucdxml", UCDXML_FILENAME)
        end

        # Directory holding the derived RLE indices for a version.
        # @param version [String]
        # @return [Pathname]
        def index_dir(version)
          version_dir(version).join("index")
        end

        def blocks_index_path(version)
          index_dir(version).join(BLOCKS_INDEX_FILENAME)
        end

        def scripts_index_path(version)
          index_dir(version).join(SCRIPTS_INDEX_FILENAME)
        end

        # True if the UCDXML file is present for this version.
        # @param version [String]
        # @return [Boolean]
        def cached?(version)
          ucdxml_path(version).exist?
        end

        # All versions currently in the cache (sorted ascending).
        # @return [Array<String>]
        def cached_versions
          return [] unless root.exist?

          root.children.select(&:directory?).map { |p| p.basename.to_s }.sort
        end

        # Create the version directory and ucdxml/index subdirs.
        # Idempotent.
        # @param version [String]
        def ensure_version_dir!(version)
          ucdxml_path(version).dirname.mkpath
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
