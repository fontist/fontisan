# frozen_string_literal: true

module Fontisan
  module Ufo
    # Conversion layer between the UFO model and fontisan's BinData
    # table layer. Two directions:
    #
    #   ToBinData.convert(ufo_font)   → Hash<tag, BinData record or bytes>
    #   FromBinData.convert(loaded_font) → Fontisan::Ufo::Font
    #
    # The ToBinData path is already implemented as Compile::* modules
    # (each table builder IS a UFO→BinData converter). This namespace
    # owns the reverse direction.
    module Convert
      autoload :FromBinData, "fontisan/ufo/convert/from_bin_data"
    end
  end
end
