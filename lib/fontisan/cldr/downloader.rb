# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"
require "zip"

module Fontisan
  module Cldr
    # Fetches CLDR JSON archives from unicode-org/cldr-json GitHub releases
    # and unpacks them into the cache.
    #
    # Single entry point: `Downloader.download(version, force:)`.
    # Idempotent unless `force: true`. Returns the path to the extracted
    # `main/` characters directory.
    module Downloader
      class << self
        # Download and unpack CLDR JSON for `version`.
        #
        # @param version [String] e.g. "46.0.0"
        # @param force [Boolean] if false and cache already has the
        #   extracted files, return without re-fetching.
        # @return [Pathname] path to the extracted main/ characters dir
        # @raise [DownloadError] on HTTP failure or zip extraction failure
        def download(version, force: false)
          target = CacheManager.characters_main_dir(version)
          return target if target.exist? && !force

          CacheManager.ensure_version_dir!(version)
          zip_data = fetch_zip(version)
          extract_archive(zip_data, CacheManager.json_dir(version))
          target
        end

        private

        def fetch_zip(version)
          uri = URI(Config.archive_url_for(version))
          response = Net::HTTP.get_response(uri)
          unless response.is_a?(Net::HTTPSuccess)
            raise DownloadError,
                  "GET #{uri} returned HTTP #{response.code}: #{response.message}"
          end

          body = response.body
          if body.nil? || body.empty?
            raise DownloadError, "GET #{uri} returned an empty body"
          end

          body
        rescue StandardError => e
          raise e if e.is_a?(DownloadError)

          raise DownloadError, "Failed to fetch #{uri}: #{e.message}"
        end

        def extract_archive(zip_data, target_dir)
          Tempfile.create(["fontisan-cldr", ".zip"]) do |tmp|
            tmp.binmode
            tmp.write(zip_data)
            tmp.flush
            tmp.rewind

            target_dir.mkpath
            Zip::File.open(tmp.path) do |zip|
              zip.each do |entry|
                next unless entry.file?

                out = target_dir.join(entry.name)
                out.dirname.mkpath
                entry.extract(out.to_s) { true } # overwrite
              end
            end
          end
        end
      end
    end
  end
end
