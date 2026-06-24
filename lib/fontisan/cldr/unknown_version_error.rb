# frozen_string_literal: true

module Fontisan
  module Cldr
    # Raised by Cldr::VersionResolver when a user-supplied version string
    # is not in Cldr::Config.known_versions.
    class UnknownVersionError < Cldr::Error; end
  end
end
