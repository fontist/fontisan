# frozen_string_literal: true

module Fontisan
  module Ucd
    # Raised by Ucd::VersionResolver when a user-supplied version string
    # is not in Ucd::Config.known_versions.
    class UnknownVersionError < Ucd::Error; end
  end
end
