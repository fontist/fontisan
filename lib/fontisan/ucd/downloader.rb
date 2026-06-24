# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"
require "zip"

module Fontisan
  module Ucd
    # Fetches UCDXML zips from unicode.org and unpacks them into the cache.
    #
    # Single entry point: `Downloader.download(version, force:)`.
    # Idempotent unless `force: true`. Returns the path to the unpacked
    # `ucd.all.flat.xml`.
    module Downloader
      UCDXML_ZIP_ENTRY = "ucd.all.flat.xml"
      private_constant :UCDXML_ZIP_ENTRY

      class << self
        # Download and unpack UCDXML for `version`.
        #
        # @param version [String] e.g. "17.0.0"
        # @param force [Boolean] if false and cache already has the file,
        #   return the existing path without re-fetching.
        # @return [Pathname] path to the unpacked ucd.all.flat.xml
        # @raise [DownloadError] on HTTP failure or zip extraction failure
        def download(version, force: false)
          target = CacheManager.ucdxml_path(version)
          return target if target.exist? && !force

          CacheManager.ensure_version_dir!(version)
          zip_data = fetch_zip(version)
          extract_xml(zip_data, target)
          target
        end

        private

        def fetch_zip(version)
          uri = URI(Config.ucdxml_url_for(version))
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

        def extract_xml(zip_data, target)
          Tempfile.create(["fontisan-ucd", ".zip"]) do |tmp|
            tmp.binmode
            tmp.write(zip_data)
            tmp.flush
            tmp.rewind

            write_xml_entry(tmp.path, target)
          end
        end

        def write_xml_entry(zip_path, target)
          Zip::File.open(zip_path) do |zip|
            entry = zip.find_entry(UCDXML_ZIP_ENTRY) ||
              zip.glob("#{UCDXML_ZIP_ENTRY}*", include_directories: false).first
            unless entry
              raise DownloadError,
                    "UCDXML zip did not contain #{UCDXML_ZIP_ENTRY.inspect}"
            end

            # Atomic-ish: write to .part then rename.
            partial = target.sub_ext(".xml.part")
            zip.extract(entry, partial.to_s) { true } # overwrite
            File.rename(partial.to_s, target.to_s)
          end
        end
      end
    end
  end
end
