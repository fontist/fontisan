# frozen_string_literal: true

module Fontisan
  module Cldr
    # Raised by Cldr::Downloader when the upstream HTTP fetch or the zip
    # extraction fails.
    class DownloadError < Cldr::Error; end
  end
end
