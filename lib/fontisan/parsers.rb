# frozen_string_literal: true

# Autoload hub for the Fontisan::Parsers namespace.

module Fontisan
  module Parsers
    autoload :DfontParser, "fontisan/parsers/dfont_parser"
    autoload :Tag, "fontisan/parsers/tag"
  end
end
