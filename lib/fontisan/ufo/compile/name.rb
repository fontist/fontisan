# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `name` table from UFO fontinfo data.
      # Writes Windows-Unicode (platform 3, encoding 1) name records
      # for the standard 6 name IDs (copyright, family, subfamily,
      # unique ID, full name, version, PostScript name).
      #
      # BinData's Tables::Name structure doesn't make construction
      # from a record list easy (it has a custom after_read_hook and
      # a `rest :string_storage`); this builder produces the bytes
      # directly so we don't fight the BinData shape.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/name
      module Name
        PLATFORM_WINDOWS_UNICODE = 3
        ENCODING_WINDOWS_UNICODE_BMP = 1
        LANGUAGE_WINDOWS_ENGLISH_US = 0x0409

        # @param font [Fontisan::Ufo::Font]
        # @return [String] the name table bytes
        def self.build(font, **_opts)
          records = default_records(font)
          format0_bytes(records)
        end

        # @param font [Fontisan::Ufo::Font] (used without glyph info)
        # @return [Array<Hash{name_id: Integer, value: String}>]
        def self.default_records(font)
          family = font.info.family_name || "Untitled"
          subfamily = font.info.style_name || "Regular"
          ps_name = font.info.postscript_font_name || "#{family}-#{subfamily}"
          full_name = "#{family} #{subfamily}".strip
          major = font.info.version_major || 0
          minor = font.info.version_minor || 0
          version_str = "Version #{major}.#{minor}"
          unique_id = "#{family}-#{subfamily};#{version_str}"
          copyright = font.info.copyright || ""

          [
            { name_id: 0, value: copyright }, # copyright
            { name_id: 1, value: family },    # family
            { name_id: 2, value: subfamily }, # subfamily
            { name_id: 3, value: unique_id }, # unique ID
            { name_id: 4, value: full_name }, # full name
            { name_id: 5, value: version_str }, # version
            { name_id: 6, value: ps_name }, # PostScript name
          ]
        end

        def self.format0_bytes(records)
          # Strings are stored UTF-16BE on disk (Windows Unicode).
          encoded = records.map { |r| r[:value].encode("UTF-16BE").force_encoding("BINARY") }
          storage = encoded.join
          storage_offset = 6 + (records.size * 12)

          header = [0, records.size, storage_offset].pack("nnn")
          body = +""
          offset = 0
          records.zip(encoded).each do |r, bytes|
            body << [
              PLATFORM_WINDOWS_UNICODE,
              ENCODING_WINDOWS_UNICODE_BMP,
              LANGUAGE_WINDOWS_ENGLISH_US,
              r[:name_id],
              bytes.bytesize,
              offset,
            ].pack("nnnnnn")
            offset += bytes.bytesize
          end

          header + body + storage
        end
        private_class_method :format0_bytes, :default_records
      end
    end
  end
end
