# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::InfoCommand do
  # Helper to build minimal name table
  def build_name_table(names = {})
    format = [0].pack("n")
    count = [names.size].pack("n")
    string_offset = [6 + (names.size * 12)].pack("n")

    records = "".b
    strings = "".b
    offset = 0

    names.each do |name_id, string|
      platform_id = [3].pack("n")
      encoding_id = [1].pack("n")
      language_id = [0x0409].pack("n")
      name_id_bytes = [name_id].pack("n")

      utf16_string = string.encode("UTF-16BE").b
      length = [utf16_string.bytesize].pack("n")
      offset_bytes = [offset].pack("n")

      records += platform_id + encoding_id + language_id +
        name_id_bytes + length + offset_bytes
      strings += utf16_string
      offset += utf16_string.bytesize
    end

    format + count + string_offset + records + strings
  end

  # Helper to build minimal OS/2 table
  def build_os2_table(vendor_id: "TEST", type_flags: 0)
    version = [4].pack("n")
    # Padding up to vendor_id at offset 58
    # version(2) + xAvgCharWidth(2) + usWeightClass(2) + usWidthClass(2) +
    # fsType(2) + subscript fields(8) + superscript fields(8) + strikeout(4) +
    # sFamilyClass(2) + panose(10) + unicode ranges(16) = 58 bytes total before vendor_id
    padding_before = "\x00" * 56
    vendor_id_bytes = vendor_id.ljust(4, " ")
    # fsSelection(2) + usFirstChar(2) + usLastChar(2) = 6 bytes
    padding_middle = [type_flags].pack("n") + ("\x00" * 4)
    # Rest of table
    padding_after = "\x00" * 30

    version + padding_before + vendor_id_bytes + padding_middle + padding_after
  end

  # Helper to build minimal head table
  def build_head_table(font_revision: 1.0, units_per_em: 2048)
    version = [1, 0].pack("n2")
    revision_int = (font_revision * 65_536).to_i
    font_revision_bytes = [revision_int].pack("N")
    checksum_adjustment = [0].pack("N")
    magic_number = [0x5F0F3CF5].pack("N")
    flags = [0].pack("n")
    units_per_em_bytes = [units_per_em].pack("n")
    created = [0, 0].pack("N2")
    modified = [0, 0].pack("N2")
    x_min = [0].pack("n")
    y_min = [0].pack("n")
    x_max = [1000].pack("n")
    y_max = [1000].pack("n")
    mac_style = [0].pack("n")
    lowest_rec_ppem = [8].pack("n")
    font_direction_hint = [2].pack("n")
    index_to_loc_format = [0].pack("n")
    glyph_data_format = [0].pack("n")

    version + font_revision_bytes + checksum_adjustment + magic_number +
      flags + units_per_em_bytes + created + modified +
      x_min + y_min + x_max + y_max + mac_style +
      lowest_rec_ppem + font_direction_hint +
      index_to_loc_format + glyph_data_format
  end

  # Helper to build font with tables
  def build_font_data(tables_data = {})
    sfnt_version = [0x00010000].pack("N")
    num_tables = [tables_data.size].pack("n")
    search_range = [0].pack("n")
    entry_selector = [0].pack("n")
    range_shift = [0].pack("n")

    directory = sfnt_version + num_tables + search_range + entry_selector + range_shift

    offset = 12 + (tables_data.size * 16)
    table_entries = ""
    table_data = ""

    tables_data.each do |tag, data|
      tag_bytes = tag.ljust(4, " ")
      checksum = [0].pack("N")
      offset_bytes = [offset].pack("N")
      length = [data.bytesize].pack("N")

      table_entries += tag_bytes + checksum + offset_bytes + length
      table_data += data

      offset += data.bytesize
    end

    directory + table_entries + table_data
  end

  let(:font_data) do
    build_font_data(
      "name" => build_name_table(
        1 => "Test Family",
        2 => "Regular",
        4 => "Test Family Regular",
        6 => "TestFamily-Regular",
        5 => "Version 1.0",
        0 => "Copyright 2024",
      ),
      "OS/2" => build_os2_table(vendor_id: "TEST", type_flags: 0),
      "head" => build_head_table(font_revision: 1.5, units_per_em: 2048),
    )
  end

  let(:temp_font_file) do
    file = Tempfile.new(["test-font", ".ttf"])
    file.binmode
    file.write(font_data)
    file.close
    file
  end

  let(:command) { described_class.new(temp_font_file.path) }

  after do
    temp_font_file&.unlink
  end

  describe "#run" do
    it "returns a FontInfo instance" do
      info = command.run
      expect(info).to be_a(Fontisan::Models::FontInfo)
    end

    it "extracts font format for TrueType fonts" do
      info = command.run
      expect(info.font_format).to eq("truetype")
      expect(info.is_variable).to be false
    end

    it "extracts name table fields" do
      info = command.run
      expect(info.family_name).to eq("Test Family")
      expect(info.subfamily_name).to eq("Regular")
      expect(info.full_name).to eq("Test Family Regular")
      expect(info.postscript_name).to eq("TestFamily-Regular")
      expect(info.version).to eq("Version 1.0")
      expect(info.copyright).to eq("Copyright 2024")
    end

    it "extracts OS/2 fields" do
      info = command.run
      expect(info.vendor_id).to eq("TEST")
      expect(info.permissions).to eq("Installable")
    end

    it "extracts head fields" do
      info = command.run
      expect(info.font_revision).to be_within(0.01).of(1.5)
      expect(info.units_per_em).to eq(2048)
    end

    context "with missing tables" do
      let(:font_data) { build_font_data }

      it "does not fail" do
        expect { command.run }.not_to raise_error
      end
    end

    context "with OpenType (CFF) fonts" do
      let(:font_data) do
        build_font_data_with_sfnt([0x4F54544F].pack("N"), {})
      end

      it "detects CFF font format" do
        info = command.run
        expect(info.font_format).to eq("cff")
        expect(info.is_variable).to be false
      end
    end

    context "with variable fonts" do
      let(:font_data) do
        # Build font with fvar table
        tables = {
          "fvar" => build_fvar_table,
        }
        build_font_data(tables)
      end

      it "detects variable font" do
        info = command.run
        expect(info.font_format).to eq("truetype")
        expect(info.is_variable).to be true
      end
    end
  end

  # Helper to build font with custom sfnt version
  def build_font_data_with_sfnt(sfnt_version, tables_data)
    num_tables = [tables_data.size].pack("n")
    search_range = [0].pack("n")
    entry_selector = [0].pack("n")
    range_shift = [0].pack("n")

    directory = sfnt_version + num_tables + search_range + entry_selector + range_shift

    offset = 12 + (tables_data.size * 16)
    table_entries = ""
    table_data = ""

    tables_data.each do |tag, data|
      tag_bytes = tag.ljust(4, " ")
      checksum = [0].pack("N")
      offset_bytes = [offset].pack("N")
      length = [data.bytesize].pack("N")

      table_entries += tag_bytes + checksum + offset_bytes + length
      table_data += data

      offset += data.bytesize
    end

    directory + table_entries + table_data
  end

  # Helper to build minimal fvar table
  def build_fvar_table
    "\x00\x01\x00\x00#{"\x00" * 20}"
  end

  describe "#format_permissions" do
    it "formats installable embedding" do
      expect(command.send(:format_permissions, 0)).to eq("Installable")
    end

    it "formats restricted license embedding" do
      expect(command.send(:format_permissions, 2)).to eq("Restricted License")
    end

    it "formats preview & print embedding" do
      expect(command.send(:format_permissions, 4)).to eq("Preview & Print")
    end

    it "formats editable embedding" do
      expect(command.send(:format_permissions, 8)).to eq("Editable")
    end

    it "formats unknown embedding type" do
      expect(command.send(:format_permissions, 15)).to eq("Unknown (15)")
    end

    it "formats no subsetting flag" do
      expect(command.send(:format_permissions,
                          0x100)).to eq("Installable, No subsetting")
    end

    it "formats bitmap only flag" do
      expect(command.send(:format_permissions,
                          0x200)).to eq("Installable, Bitmap only")
    end

    it "formats multiple flags" do
      expect(command.send(:format_permissions,
                          0x300)).to eq("Installable, No subsetting, Bitmap only")
    end

    it "formats editable with no subsetting" do
      expect(command.send(:format_permissions,
                          0x108)).to eq("Editable, No subsetting")
    end

    it "formats preview & print with bitmap only" do
      expect(command.send(:format_permissions,
                          0x204)).to eq("Preview & Print, Bitmap only")
    end
  end

  describe "brief mode" do
    let(:brief_command) do
      described_class.new(temp_font_file.path, brief: true)
    end

    it "returns FontInfo model" do
      result = brief_command.run
      expect(result).to be_a(Fontisan::Models::FontInfo)
    end

    it "populates essential fields only" do
      result = brief_command.run

      # Essential fields populated
      expect(result.font_format).to eq("truetype")
      expect(result.is_variable).to be false
      expect(result.family_name).to eq("Test Family")
      expect(result.subfamily_name).to eq("Regular")
      expect(result.full_name).to eq("Test Family Regular")
      expect(result.postscript_name).to eq("TestFamily-Regular")
      expect(result.version).to eq("Version 1.0")
      expect(result.font_revision).to be_within(0.01).of(1.5)
      expect(result.units_per_em).to eq(2048)
      expect(result.vendor_id).to eq("TEST")
    end

    it "does not populate non-essential fields" do
      result = brief_command.run

      # Non-essential fields not populated
      expect(result.copyright).to be_nil
      expect(result.trademark).to be_nil
      expect(result.designer).to be_nil
      expect(result.designer_url).to be_nil
      expect(result.manufacturer).to be_nil
      expect(result.vendor_url).to be_nil
      expect(result.license_description).to be_nil
      expect(result.license_url).to be_nil
      expect(result.description).to be_nil
      expect(result.sample_text).to be_nil
      expect(result.unique_id).to be_nil
      expect(result.postscript_cid_name).to be_nil
      expect(result.preferred_family).to be_nil
      expect(result.preferred_subfamily).to be_nil
      expect(result.mac_font_menu_name).to be_nil
      expect(result.permissions).to be_nil
    end

    it "serializes to YAML correctly" do
      result = brief_command.run
      yaml = result.to_yaml

      expect(yaml).to include("family_name:")
      expect(yaml).to include("font_format:")
      expect(yaml).to include("Test Family")
    end

    it "serializes to JSON correctly" do
      result = brief_command.run
      json = JSON.parse(result.to_json)

      expect(json).to have_key("family_name")
      expect(json).to have_key("font_format")
      expect(json["family_name"]).to eq("Test Family")
      expect(json["font_format"]).to eq("truetype")
    end

    context "with variable font" do
      let(:font_data) do
        build_font_data(
          "name" => build_name_table(
            1 => "Variable Family",
            2 => "Regular",
            4 => "Variable Family Regular",
            6 => "VariableFamily-Regular",
            5 => "Version 2.0",
          ),
          "OS/2" => build_os2_table(vendor_id: "VARI"),
          "head" => build_head_table(font_revision: 2.0, units_per_em: 1000),
          "fvar" => build_fvar_table,
        )
      end

      it "detects variable font in brief mode" do
        result = brief_command.run
        expect(result.is_variable).to be true
        expect(result.font_format).to eq("truetype")
      end
    end
  end

  describe "dfont collection support" do
    let(:dfont_path) { font_fixture_path("Tamsyn", "Tamsyn7x13.dfont") }
    let(:dfont_command) { described_class.new(dfont_path) }

    it "detects dfont as collection" do
      expect(Fontisan::FontLoader.collection?(dfont_path)).to be true
    end

    it "returns CollectionInfo for dfont" do
      info = dfont_command.run
      expect(info).to be_a(Fontisan::Models::CollectionInfo)
    end

    it "extracts collection metadata for dfont" do
      info = dfont_command.run
      expect(info.collection_format).to eq("dfont")
      expect(info.num_fonts).to eq(2)
      expect(info.ttc_tag).to eq("dfnt")
      expect(info.version_string).to eq("0.0")
    end

    it "extracts all fonts from dfont collection" do
      info = dfont_command.run
      expect(info.fonts).to be_an(Array)
      expect(info.fonts.length).to eq(2)

      # Check first font
      expect(info.fonts[0]).to be_a(Fontisan::Models::FontInfo)
      expect(info.fonts[0].family_name).to eq("Tamsyn7x13")
      expect(info.fonts[0].subfamily_name).to eq("Regular")

      # Check second font
      expect(info.fonts[1]).to be_a(Fontisan::Models::FontInfo)
      expect(info.fonts[1].family_name).to eq("Tamsyn7x13")
      expect(info.fonts[1].subfamily_name).to eq("Bold")
    end

    it "calculates table sharing for dfont" do
      info = dfont_command.run
      expect(info.table_sharing).to be_a(Fontisan::Models::TableSharingInfo)
      expect(info.table_sharing.unique_tables).to be > 0
      expect(info.table_sharing.sharing_percentage).to be >= 0
    end

    it "provides font offsets as indices for dfont" do
      info = dfont_command.run
      expect(info.font_offsets).to eq([0, 1])
    end

    context "with single-font dfont" do
      let(:single_dfont_path) { "spec/fixtures/fonttools/TestDFONT.dfont" }
      let(:single_dfont_command) { described_class.new(single_dfont_path) }

      it "still treats single-font dfont as collection" do
        expect(Fontisan::FontLoader.collection?(single_dfont_path)).to be true
      end

      it "returns CollectionInfo for single-font dfont" do
        info = single_dfont_command.run
        expect(info).to be_a(Fontisan::Models::CollectionInfo)
        expect(info.num_fonts).to eq(1)
      end

      it "extracts the single font correctly" do
        info = single_dfont_command.run
        expect(info.fonts.length).to eq(1)
        expect(info.fonts[0]).to be_a(Fontisan::Models::FontInfo)
      end
    end
  end
end
