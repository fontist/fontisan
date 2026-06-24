# frozen_string_literal: true

# Autoload hub for the Fontisan::Utilities namespace.

module Fontisan
  module Utilities
    autoload :BrotliWrapper, "fontisan/utilities/brotli_wrapper"
    autoload :ChecksumCalculator, "fontisan/utilities/checksum_calculator"
  end
end
