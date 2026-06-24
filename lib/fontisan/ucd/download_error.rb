# frozen_string_literal: true

module Fontisan
  module Ucd
    # Raised by Ucd::Downloader when the upstream HTTP fetch or the zip
    # extraction fails. Caught by AuditCommand to degrade-with-warning.
    class DownloadError < Ucd::Error; end
  end
end
