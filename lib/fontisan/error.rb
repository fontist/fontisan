# frozen_string_literal: true

module Fontisan
  class Error < StandardError; end

  class InvalidFontError < Error; end

  class UnsupportedFormatError < Error; end

  class CorruptedTableError < Error; end

  class MissingTableError < Error; end

  class ParseError < Error; end

  class SubsettingError < Error; end
end
