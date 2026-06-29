# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `post` (PostScript name) table.
      # Default version is 3.0 (no per-glyph names; smallest).
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/post
      module Post
        VERSION_3_0_RAW = 0x00030000

        # @param _font [Fontisan::Ufo::Font] italic angle + underline
        #   read from info, but everything else is zero (no hinting)
        # @return [String] the post table bytes (32 bytes for v3.0)
        def self.build(font, **_opts)
          italic_angle = font.info.italic_angle || 0.0
          [
            VERSION_3_0_RAW,                       # version 3.0
            (italic_angle * 0x10000).to_i,         # italicAngle (Fixed 16.16)
            -100,                                  # underlinePosition (FUnits)
            50,                                    # underlineThickness
            0,                                     # isFixedPitch
            0,                                     # minMemType42
            0,                                     # maxMemType42
            0,                                     # minMemType1
            0, # maxMemType1
          ].pack("NNnnNNNNN")
        end
      end
    end
  end
end
