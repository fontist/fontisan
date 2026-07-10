# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff
      # CFF Standard Strings (SID 0-390).
      #
      # Source: Adobe CFF Specification 1.0 (TN 5176), Appendix A.
      # Identical to fontTools cffLib StandardStrings.
      #
      # Extracted to its own file so the data is separated from
      # the Cff class logic.
      module StandardStrings
        # The 391 CFF standard strings are a fixed spec-defined data
        # table (Adobe TN 5176 Appendix A).
        # rubocop:disable Metrics/CollectionLiteralLength
        LIST = %w[
          .notdef space exclam quotedbl numbersign
          dollar percent ampersand quoteright
          parenleft parenright asterisk plus
          comma hyphen period slash
          zero one two three four five six seven eight nine
          colon semicolon less equal greater question at
          A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
          bracketleft backslash bracketright asciicircum underscore quoteleft
          a b c d e f g h i j k l m n o p q r s t u v w x y z
          braceleft bar braceright asciitilde
          exclamdown cent sterling fraction yen florin section currency
          quotesingle quotedblleft guillemotleft guilsinglleft guilsinglright
          fi fl endash dagger daggerdbl periodcentered paragraph bullet
          quotesinglbase quotedblbase quotedblright guillemotright ellipsis
          perthousand questiondown grave acute circumflex tilde macron breve
          dotaccent dieresis ring cedilla hungarumlaut ogonek caron emdash
          AE ordfeminine Lslash Oslash OE ordmasculine
          ae dotlessi lslash oslash oe germandbls
          onesuperior twosuperior threesuperior minus multiply
          oneshalf onequarter threequarters
          questiondownsmall exclamdownsmall capitalshadow asciicircumsmall
          centinferior sterlinginferior fractionsmall zerosuperior yeninferior
          florinsmall dieresissmall caronsmall commaaccent dotlessj ae hoi
          circumflexsmall tildesmall macronsmall brevesmall dotaccentsmall
          slash ringsmall cedillasmall hungarumlautsmall ogoneksmall ringsmall
          fismall flsmall Acutesmall Hungarumlautsmall Caronsmall Cedillasmall
          Brevesmall Macronsmall Dieresissmall Ogoneksmall Circumflexsmall
          Tildesmall Ringsmall Gravesmall Lslashsmall OEsmall florin y z
          commasuperior figuredash hookleft afii00208
          afii10017 afii10018 afii10019 afii10020 afii10021 afii10022 afii10023
          afii10024 afii10025 afii10026 afii10027 afii10028 afii10029 afii10030
          afii10031 afii10032 afii10033 afii10034 afii10035 afii10036 afii10037
          afii10038 afii10039 afii10040 afii10041 afii10042 afii10043 afii10044
          afii10045 afii10046 afii10047 afii10048 afii10049
          afii10065 afii10066 afii10067 afii10068 afii10069 afii10070 afii10071
          afii10072 afii10073 afii10074 afii10075 afii10076 afii10077 afii10078
          afii10079 afii10080 afii10081 afii10082 afii10083 afii10084 afii10085
          afii10086 afii10087 afii10088 afii10089 afii10090 afii10091 afii10092
          afii10093 afii10094 afii10095 afii10096 afii10097
          afii10071.alt afii10061.alt afii10101 afii10102 afii10103 afii10104
          afii10105 afii10106 afii10107 afii10108 afii10109 section.alt afii10110
          afii10193 afii10194 afii10195 afii10196 afii10050 afii10098
          afii10024.alt afii10050.alt Wgrave Wacute Wdieresis Ygrave
          afii10051 afii10052 afii10053 afii10054 afii10055 afii10056 afii10057
          afii10058 afii10059 afii10060 afii10061
          afii10146.alt afii10031.alt afii10147.alt
          afii10146 afii10147 afii10148 afii10192 afii10846
          afii57799 afii57801 afii57800 afii57802 afii57803 afii57804 afii57805
          afii57806 afii57807 afii57808 afii57809 afii57810 afii57811 afii57812
          afii57813 afii57814 afii57815 afii57816 afii57817 afii57818
          afii57388 afii57403 afii57407 afii57409 afii57410 afii57411 afii57412
          afii57413 afii57414 afii57415 afii57416 afii57417 afii57418 afii57419
          afii57420 afii57421 afii57422 afii57423 afii57424 afii57425 afii57426
          afii57427 afii57428 afii57429 afii57430 afii57431 afii57432 afii57433
          afii57434
          Afii61264 Afii61265 Afii61266 afii63167
          afii57511 afii57512 afii57513 afii57514 afii57515 afii57516 afii57517
          afii57518 afii57519 afii57520 afii57521 afii64237 afii64238
          exclamdouble uni204A uni2080 uni2081 uni2082 uni2083 uni2084
        ].freeze
        # rubocop:enable Metrics/CollectionLiteralLength

        COUNT = 391
      end
    end
  end
end
