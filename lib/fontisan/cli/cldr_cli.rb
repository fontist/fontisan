# frozen_string_literal: true

require "thor"

module Fontisan
  # Thor subcommand for managing the local CLDR (Common Locale Data
  # Repository) cache used by `fontisan audit` for per-language coverage.
  #
  #   fontisan cldr download [VERSION]   fetch + index CLDR exemplars
  #   fontisan cldr status               show what's cached
  #   fontisan cldr path [VERSION]       print local cache path
  #   fontisan cldr list                 list known versions
  #   fontisan cldr remove VERSION       delete a cached version
  #
  # With no arguments, `download` resolves the configured default version
  # (see lib/fontisan/config/cldr.yml).
  class CldrCli < Thor
    desc "download [VERSION]",
         "Download and index CLDR exemplar characters (default: configured default version)"
    option :force, type: :boolean, default: false,
                   desc: "Re-download even if already cached"
    option :latest, type: :boolean, default: false,
                    desc: "Probe GitHub releases for the latest version"
    def download(version = nil)
      intent = resolve_intent(version, options[:latest])
      actual = Cldr::VersionResolver.resolve(intent)

      Cldr::Downloader.download(actual, force: options[:force])
      Cldr::IndexBuilder.build(actual) unless index_present?(actual)
      puts "CLDR #{actual} ready at: #{Cldr::CacheManager.version_dir(actual)}"
    rescue Cldr::Error => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    desc "status", "Show cached CLDR versions and default version"
    def status
      cached = Cldr::CacheManager.cached_versions
      puts "Default version: #{Cldr::Config.default_version}"
      puts "Cache root:      #{Cldr::CacheManager.root}"
      puts "Cached versions: #{cached.empty? ? '(none)' : cached.join(', ')}"
    end

    desc "path [VERSION]", "Print local cache directory for a version"
    def path(version = nil)
      actual = Cldr::VersionResolver.resolve(version)
      puts Cldr::CacheManager.version_dir(actual)
    rescue Cldr::UnknownVersionError => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    desc "list", "List CLDR versions known to this Fontisan release"
    def list
      Cldr::Config.known_versions.each { |v| puts v }
    end

    desc "remove VERSION", "Remove a cached CLDR version"
    def remove(version)
      Cldr::VersionResolver.validate!(version)
      unless Cldr::CacheManager.cached?(version)
        warn "Version #{version} is not cached; nothing to remove."
        return
      end

      Cldr::CacheManager.remove_version(version)
      puts "Removed CLDR #{version}."
    rescue Cldr::UnknownVersionError => e
      warn "ERROR: #{e.message}"
      exit 1
    end

    private

    def resolve_intent(version, latest)
      return :latest if latest && version.nil?

      version
    end

    def index_present?(version)
      Cldr::CacheManager.languages_index_path(version).exist?
    end
  end
end
