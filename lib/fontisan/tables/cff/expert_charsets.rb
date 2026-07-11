# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff
      # Predefined CFF charset glyph name arrays per Adobe TN 5176.
      #
      # When the Top DICT charset offset is 0 (ISOAdobe), 1 (Expert),
      # or 2 (ExpertSubset), the font uses a predefined charset instead
      # of a custom one. These arrays map GID → glyph name.
      #
      # Source: Adobe CFF Specification 1.0 (TN 5176), Section 19.
      # Identical to fontTools cffLib expertCharset / expertSubsetCharset.
      module ExpertCharsets
        # rubocop:disable Metrics/CollectionLiteralLength
        EXPERT = %w[
          .notdef space exclamsmall Hungarumlautsmall
          dollaroldstyle dollarsuperior ampersandsmall Acutesmall
          parenleftsuperior parenrightsuperior twodotenleader
          onedotenleader comma hyphen period fraction
          zerooldstyle oneoldstyle twooldstyle threeoldstyle
          fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle
          eightoldstyle nineoldstyle colon semicolon commasuperior
          threequartersemdash periodsuperior questionsmall
          asuperior bsuperior centsuperior dsuperior esuperior
          isuperior lsuperior msuperior nsuperior osuperior
          rsuperior ssuperior tsuperior ff ffi ffl
          parenleftinferior parenrightinferior Circumflexsmall
          hyphensuperior Gravesmall Asmall Bsmall Csmall Dsmall
          Esmall Fsmall Gsmall Hsmall Ismall Jsmall Ksmall Lsmall
          Msmall Nsmall Osmall Psmall Qsmall Rsmall Ssmall Tsmall
          Usmall Vsmall Wsmall Xsmall Ysmall Zsmall colonmonetary
          onefitted rupiah Tildesmall exclamdownsmall centinferior
          lirasuperior Brevesmall Caronsmall Dotaccentsmall Macronsmall
          figuredash hypheninferior Ogoneksmall Ringsmall Cedillasmall
          questiondownsmall oneeighth threeeighths fiveeighths
          seveneighths onethird twothirds zerosuperior foursuperior
          fivesuperior sixsuperior sevensuperior eightsuperior
          ninesuperior zeroinferior oneinferior twoinferior
          threeinferior fourinferior fiveinferior sixinferior
          seveninferior eightinferior nineinferior centinferior
          dollarinferior periodinferior commainferior Agravesmall
          Aacutesmall Acircumflexsmall Atildesmall Adieresissmall
          Aringsmall AEsmall Ccedillasmall Egravesmall Eacutesmall
          Ecircumflexsmall Edieresissmall Igravesmall Iacutesmall
          Icircumflexsmall Idieresissmall Ethsmall Ntildesmall
          Ogravesmall Oacutesmall Ocircumflexsmall Otildesmall
          Odieresissmall OEsmall Oslashsmall Ugravesmall Uacutesmall
          Ucircumflexsmall Udieresissmall Yacutesmall Thornsmall
          Ydieresissmall 001.000 001.001 001.002 001.003
          Black Bold Book Light Medium Regular Roman Semibold
        ].freeze

        EXPERT_SUBSET = %w[
          .notdef space dollaroldstyle dollarsuperior
          parenleftsuperior parenrightsuperior twodotenleader
          onedotenleader comma hyphen period fraction
          zerooldstyle oneoldstyle twooldstyle threeoldstyle
          fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle
          eightoldstyle nineoldstyle colon semicolon commasuperior
          threequartersemdash periodsuperior asuperior bsuperior
          centsuperior dsuperior esuperior isuperior lsuperior
          msuperior nsuperior osuperior rsuperior ssuperior
          tsuperior ff ffi ffl parenleftinferior parenrightinferior
          hyphensuperior colonmonetary onefitted rupiah
          centinferior lirasuperior Brevesmall Caronsmall
          figuredash hypheninferior oneeighth threeeighths
          fiveeighths seveneighths onethird twothirds zerosuperior
          foursuperior fivesuperior sixsuperior sevensuperior
          eightsuperior ninesuperior zeroinferior oneinferior
          twoinferior threeinferior fourinferior fiveinferior
          sixinferior seveninferior eightinferior nineinferior
          centinferior dollarinferior periodinferior commainferior
          Agravesmall Aacutesmall Acircumflexsmall Adieresissmall
          AEsmall Ccedillasmall Egravesmall Eacutesmall
          Ecircumflexsmall Edieresissmall Igravesmall Iacutesmall
        ].freeze
        # rubocop:enable Metrics/CollectionLiteralLength

        EXPERT_COUNT = 167
        EXPERT_SUBSET_COUNT = 87
      end
    end
  end
end
