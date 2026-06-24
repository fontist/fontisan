# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Namespace for UCDXML deserialization models.
    #
    # These classes deserialize the upstream UCDXML flat file
    # (https://www.unicode.org/Public/<version>/ucdxml/ucd.all.flat.zip)
    # into Ruby objects. They are used by Fontisan::Ucd::IndexBuilder to
    # derive compact run-length-encoded indices for Unicode block and
    # script lookup.
    module Ucd
      autoload :UcdChar, "fontisan/models/ucd/ucd_char"
      autoload :Ucd,     "fontisan/models/ucd/ucd"
    end
  end
end
