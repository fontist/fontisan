# frozen_string_literal: true

require "thor"

module Fontisan
  # Thor subcommand for managing the local UCD (Unicode Character
  # Database) cache used by `fontisan audit`.
  #
  #   fontisan ucd download [VERSION]   fetch + index UCDXML
  #   fontisan ucd status               show what's cached
  #   fontisan ucd path [VERSION]       print local cache path
  #   fontisan ucd list                 list known versions
  #   fontisan ucd remove VERSION       delete a cached version
  #
  # With no arguments, `download` resolves the configured default version
  # (see lib/fontisan/config/ucd.yml).
  class UcdCli < Thor
    desc "download [VERSION]",
         "Download and index UCDXML (default: configured default version)"
    option :force, type: :boolean, default: false,
                   desc: "Re-download even if already cached"
    option :latest, type: :boolean, default: false,
                    desc: "Probe unicode.org for the latest version"
    # Download (and index) UCDXML for a version.
    #
    # @param version [String, nil] explicit version, or omit for default
    def download(version = nil)
      intent = resolve_intent(version, options[:latest])
      actual = Ucd::VersionResolver.resolve(intent)

      path = Ucd::Downloader.download(actual, force: options[:force])
      Ucd::IndexBuilder.build(actual) unless index_present?(actual)
      puts "UCD #{actual} ready at: #{path}"
    rescue Ucd::Error => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    desc "status", "Show cached UCD versions and default version"
    # Print a one-screen summary of the local cache state.
    def status
      cached = Ucd::CacheManager.cached_versions
      puts "Default version: #{Ucd::Config.default_version}"
      puts "Cache root:      #{Ucd::CacheManager.root}"
      puts "Cached versions: #{cached.empty? ? '(none)' : cached.join(', ')}"
    end

    desc "path [VERSION]", "Print local cache directory for a version"
    # Print the cache directory path for a version (default: default version).
    #
    # @param version [String, nil]
    def path(version = nil)
      actual = Ucd::VersionResolver.resolve(version)
      puts Ucd::CacheManager.version_dir(actual)
    rescue Ucd::UnknownVersionError => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    desc "list", "List UCD versions known to this Fontisan release"
    # Print the curated list of versions this Fontisan release supports.
    def list
      Ucd::Config.known_versions.each { |v| puts v }
    end

    desc "remove VERSION", "Remove a cached UCD version"
    # Delete one cached version. No-op if absent.
    #
    # @param version [String]
    def remove(version)
      Ucd::VersionResolver.validate!(version)
      unless Ucd::CacheManager.cached?(version)
        warn "Version #{version} is not cached; nothing to remove."
        return
      end

      Ucd::CacheManager.remove_version(version)
      puts "Removed UCD #{version}."
    rescue Ucd::UnknownVersionError => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    private

    def resolve_intent(version, latest)
      return :latest if latest && version.nil?

      version
    end

    def index_present?(version)
      Ucd::CacheManager.blocks_index_path(version).exist? &&
        Ucd::CacheManager.scripts_index_path(version).exist?
    end
  end
end
