# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Formatters::TextFormatter do
  let(:formatter) { described_class.new }

  describe "#format" do
    context "with FontInfo model" do
      let(:font_info) do
        Fontisan::Models::FontInfo.new.tap do |info|
          info.font_format = "truetype"
          info.is_variable = false
          info.family_name = "Test Font"
          info.subfamily_name = "Regular"
          info.full_name = "Test Font Regular"
          info.postscript_name = "TestFont-Regular"
          info.version = "Version 1.0"
          info.vendor_id = "TEST"
          info.font_revision = 1.5
          info.units_per_em = 1000
          info.permissions = "Installable"
        end
      end

      it "formats font info as text" do
        result = formatter.format(font_info)

        expect(result).to include("Font type:                TrueType")
        expect(result).to include("Family:                   Test Font")
        expect(result).to include("Subfamily:                Regular")
        expect(result).to include("Full name:                Test Font Regular")
        expect(result).to include("PostScript name:          TestFont-Regular")
        expect(result).to include("Version:                  Version 1.0")
        expect(result).to include("Vendor ID:                TEST")
        expect(result).to include("Font revision:            1.5")
        expect(result).to include("Units per em:             1000")
        expect(result).to include("Permissions:              Installable")
      end

      it "displays font type first" do
        result = formatter.format(font_info)
        lines = result.split("\n")

        expect(lines.first).to include("Font type:")
      end

      it "omits nil fields" do
        font_info.designer = nil
        result = formatter.format(font_info)

        expect(result).not_to include("Designer:")
      end

      it "omits empty string fields" do
        font_info.copyright = ""
        result = formatter.format(font_info)

        expect(result).not_to include("Copyright:")
      end

      it "formats float with trailing zeros removed" do
        font_info.font_revision = 2.0
        result = formatter.format(font_info)

        expect(result).to include("Font revision:            2")
      end

      it "formats float with decimal precision" do
        font_info.font_revision = 1.12345
        result = formatter.format(font_info)

        expect(result).to include("Font revision:            1.12345")
      end

      it "formats all available fields" do
        font_info.font_format = "cff"
        font_info.is_variable = true
        font_info.postscript_cid_name = "TestCID"
        font_info.preferred_family = "Test Preferred"
        font_info.preferred_subfamily = "Preferred Regular"
        font_info.mac_font_menu_name = "Test Menu"
        font_info.unique_id = "TEST-001"
        font_info.description = "A test font"
        font_info.designer = "John Doe"
        font_info.designer_url = "https://example.com/designer"
        font_info.manufacturer = "Test Corp"
        font_info.vendor_url = "https://example.com"
        font_info.trademark = "Test TM"
        font_info.copyright = "Copyright 2024"
        font_info.license_description = "Open License"
        font_info.license_url = "https://example.com/license"
        font_info.sample_text = "The quick brown fox"

        result = formatter.format(font_info)

        expect(result).to include("Font type:                OpenType (CFF) (Variable)")
        expect(result).to include("PostScript CID name:      TestCID")
        expect(result).to include("Preferred family:         Test Preferred")
        expect(result).to include("Preferred subfamily:      Preferred Regular")
        expect(result).to include("Mac font menu name:       Test Menu")
        expect(result).to include("Unique ID:                TEST-001")
        expect(result).to include("Description:              A test font")
        expect(result).to include("Designer:                 John Doe")
        expect(result).to include("Designer URL:             https://example.com/designer")
        expect(result).to include("Manufacturer:             Test Corp")
        expect(result).to include("Vendor URL:               https://example.com")
        expect(result).to include("Trademark:                Test TM")
        expect(result).to include("Copyright:                Copyright 2024")
        expect(result).to include("License Description:      Open License")
        expect(result).to include("License URL:              https://example.com/license")
        expect(result).to include("Sample text:              The quick brown fox")
      end
    end

    context "with TableInfo model" do
      let(:table_info) do
        Fontisan::Models::TableInfo.new.tap do |info|
          info.sfnt_version = "TrueType (0x00010000)"
          info.num_tables = 3
          info.tables = [
            Fontisan::Models::TableEntry.new(
              tag: "head",
              length: 54,
              offset: 100,
              checksum: 0x12345678,
            ),
            Fontisan::Models::TableEntry.new(
              tag: "name",
              length: 1234,
              offset: 200,
              checksum: 0xABCDEF00,
            ),
            Fontisan::Models::TableEntry.new(
              tag: "OS/2",
              length: 96,
              offset: 1500,
              checksum: 0x11111111,
            ),
          ]
        end
      end

      it "formats table info as text" do
        result = formatter.format(table_info)

        expect(result).to include("SFNT Version: TrueType (0x00010000)")
        expect(result).to include("Number of tables: 3")
        expect(result).to include("Tables:")
      end

      it "formats table entries with alignment" do
        result = formatter.format(table_info)

        expect(result).to include("head          54 bytes  (offset: 100, checksum: 0x12345678)")
        expect(result).to include("name        1234 bytes  (offset: 200, checksum: 0xABCDEF00)")
        expect(result).to include("OS/2          96 bytes  (offset: 1500, checksum: 0x11111111)")
      end

      it "aligns tags based on longest tag length" do
        result = formatter.format(table_info)
        lines = result.split("\n")

        # Find table entry lines (they start with spaces)
        table_lines = lines.select { |l| l.start_with?("  ") }

        # Verify all tags are aligned (OS/2 is 4 chars, longest)
        expect(table_lines[0]).to match(/^  head\s+/)
        expect(table_lines[1]).to match(/^  name\s+/)
        expect(table_lines[2]).to match(%r{^  OS/2\s+})
      end
    end

    context "with GlyphInfo model" do
      let(:glyph_info) do
        Fontisan::Models::GlyphInfo.new.tap do |info|
          info.glyph_count = 5
          info.glyph_names = [".notdef", "space", "exclam", "question", "A"]
          info.source = "post_2.0"
        end
      end

      it "formats glyph info as text" do
        result = formatter.format(glyph_info)

        expect(result).to include("Glyph count: 5")
        expect(result).to include("Source: post_2.0")
        expect(result).to include("Glyph names:")
      end

      it "formats glyph names with indices" do
        result = formatter.format(glyph_info)

        expect(result).to include("      0  .notdef")
        expect(result).to include("      1  space")
        expect(result).to include("      2  exclam")
        expect(result).to include("      3  question")
        expect(result).to include("      4  A")
      end

      it "right-aligns glyph indices" do
        result = formatter.format(glyph_info)
        lines = result.split("\n")

        # Find glyph name lines
        glyph_lines = lines.select { |l| l.match(/^\s+\d+\s+\S/) }

        # Verify indices are right-aligned to 5 characters
        expect(glyph_lines[0]).to match(/^\s+0\s/)
        expect(glyph_lines[4]).to match(/^\s+4\s/)
      end

      context "with empty glyph names" do
        let(:empty_glyph_info) do
          Fontisan::Models::GlyphInfo.new.tap do |info|
            info.glyph_count = 0
            info.glyph_names = []
            info.source = "none"
          end
        end

        it "displays no glyph name information message" do
          result = formatter.format(empty_glyph_info)

          expect(result).to include("No glyph name information available")
          expect(result).to include("Source: none")
          expect(result).not_to include("Glyph names:")
        end
      end
    end

    context "with other objects" do
      it "returns to_s for unknown objects" do
        obj = "test string"
        result = formatter.format(obj)

        expect(result).to eq("test string")
      end
    end
  end

  describe "field alignment" do
    it "aligns labels to 25 characters" do
      font_info = Fontisan::Models::FontInfo.new
      font_info.family_name = "Test"

      result = formatter.format(font_info)

      # "Family:" should be padded to 25 chars
      expect(result).to match(/^Family:\s{19}Test$/)
    end
  end

  describe "float formatting" do
    let(:font_info) { Fontisan::Models::FontInfo.new }

    it "handles nil float values" do
      font_info.font_revision = nil
      result = formatter.format(font_info)

      expect(result).not_to include("Font revision:")
    end

    it "removes trailing zeros" do
      font_info.font_revision = 1.50000
      result = formatter.format(font_info)

      expect(result).to include("Font revision:            1.5")
    end

    it "removes trailing decimal point" do
      font_info.font_revision = 2.00000
      result = formatter.format(font_info)

      expect(result).to include("Font revision:            2")
    end

    it "preserves significant decimals" do
      font_info.font_revision = 1.23456
      result = formatter.format(font_info)

      expect(result).to include("Font revision:            1.23456")
    end
  end
end
