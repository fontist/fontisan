# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Fontisan::Cli do
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
    padding_before = "\x00" * 56
    vendor_id_bytes = vendor_id.ljust(4, " ")
    padding_middle = [type_flags].pack("n") + ("\x00" * 4)
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

  # Helper to build post table version 2.0
  def build_post_table_v2(glyph_names)
    version = [0x00020000].pack("N") # Version 2.0
    italic_angle = [0].pack("N")
    underline_position = [0].pack("n")
    underline_thickness = [0].pack("n")
    is_fixed_pitch = [0].pack("N")
    min_mem_type42 = [0].pack("N")
    max_mem_type42 = [0].pack("N")
    min_mem_type1 = [0].pack("N")
    max_mem_type1 = [0].pack("N")

    header = version + italic_angle + underline_position + underline_thickness +
      is_fixed_pitch + min_mem_type42 + max_mem_type42 +
      min_mem_type1 + max_mem_type1

    # Number of glyphs
    num_glyphs = [glyph_names.length].pack("n")

    # Glyph name indices
    indices = ""
    custom_names = ""
    custom_name_index = 258 # Custom names start at index 258

    glyph_names.each do |name|
      # Check if this is a standard name
      std_index = Fontisan::Tables::Post::STANDARD_NAMES.index(name)
      if std_index
        indices += [std_index].pack("n")
      else
        indices += [custom_name_index].pack("n")
        # Add custom name as Pascal string
        custom_names += [name.length].pack("C") + name
        custom_name_index += 1
      end
    end

    header + num_glyphs + indices + custom_names
  end

  let(:font_data) do
    build_font_data(
      "name" => build_name_table(
        1 => "Test Family",
        2 => "Regular",
        4 => "Test Family Regular",
        6 => "TestFamily-Regular",
      ),
      "OS/2" => build_os2_table(vendor_id: "TEST"),
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

  after do
    temp_font_file&.unlink
  end

  describe "#version" do
    it "displays version information" do
      expect do
        described_class.start(["version"])
      end.to output(/Fontisan version/).to_stdout
    end

    it "is the default task" do
      expect do
        described_class.start([])
      end.to output(/Commands:|fontisan version/).to_stdout
    end
  end

  describe "#info" do
    context "with text format (default)" do
      it "outputs font information as text" do
        output = capture_output do
          described_class.start(["info", temp_font_file.path])
        end

        expect(output).to include("Family:")
        expect(output).to include("Test Family")
        expect(output).to include("Subfamily:")
        expect(output).to include("Regular")
      end
    end

    context "with yaml format" do
      it "outputs font information as YAML" do
        output = capture_output do
          described_class.start(["info", temp_font_file.path, "--format",
                                 "yaml"])
        end

        expect(output).to include("family_name: Test Family")
        expect(output).to include("subfamily_name: Regular")
      end

      it "works with short option -f" do
        output = capture_output do
          described_class.start(["info", temp_font_file.path, "-f", "yaml"])
        end

        expect(output).to include("family_name:")
      end
    end

    context "with json format" do
      it "outputs font information as JSON" do
        output = capture_output do
          described_class.start(["info", temp_font_file.path, "--format",
                                 "json"])
        end

        expect(output).to include('"family_name":"Test Family"')
        expect(output).to include('"subfamily_name":"Regular"')
      end
    end

    context "with quiet option" do
      it "suppresses output" do
        output = capture_output do
          described_class.start(["info", temp_font_file.path, "--quiet"])
        end

        expect(output).to be_empty
      end

      it "works with short option -q" do
        output = capture_output do
          described_class.start(["info", temp_font_file.path, "-q"])
        end

        expect(output).to be_empty
      end
    end

    context "with file not found" do
      it "exits with error" do
        expect do
          capture_output_and_error do
            described_class.start(["info", "nonexistent.ttf"])
          end
        end.to raise_error(SystemExit)
      end

      it "shows error message without verbose" do
        stderr = capture_error do
          expect do
            described_class.start(["info", "nonexistent.ttf"])
          end.to raise_error(SystemExit)
        end

        expect(stderr).to include("File not found")
      end

      it "raises full exception with verbose" do
        expect do
          described_class.start(["info", "nonexistent.ttf", "--verbose"])
        end.to raise_error(Errno::ENOENT)
      end

      it "suppresses error with quiet" do
        stderr = capture_error do
          expect do
            described_class.start(["info", "nonexistent.ttf", "--quiet"])
          end.to raise_error(SystemExit)
        end

        expect(stderr).to be_empty
      end
    end
  end

  describe "#tables" do
    context "with text format (default)" do
      it "outputs table information as text" do
        output = capture_output do
          described_class.start(["tables", temp_font_file.path])
        end

        expect(output).to include("SFNT Version:")
        expect(output).to include("Number of tables:")
        expect(output).to include("Tables:")
        expect(output).to include("name")
        expect(output).to include("OS/2")
        expect(output).to include("head")
      end
    end

    context "with yaml format" do
      it "outputs table information as YAML" do
        output = capture_output do
          described_class.start(["tables", temp_font_file.path, "--format",
                                 "yaml"])
        end

        expect(output).to include("sfnt_version:")
        expect(output).to include("num_tables:")
        expect(output).to include("tables:")
      end
    end

    context "with json format" do
      it "outputs table information as JSON" do
        output = capture_output do
          described_class.start(["tables", temp_font_file.path, "--format",
                                 "json"])
        end

        expect(output).to include('"sfnt_version"')
        expect(output).to include('"num_tables"')
        expect(output).to include('"tables"')
      end
    end

    context "with quiet option" do
      it "suppresses output" do
        output = capture_output do
          described_class.start(["tables", temp_font_file.path, "--quiet"])
        end

        expect(output).to be_empty
      end
    end
  end

  describe "#glyphs" do
    let(:glyph_names) { [".notdef", "space", "exclam", "question"] }
    let(:font_data) do
      build_font_data("post" => build_post_table_v2(glyph_names))
    end

    context "with text format (default)" do
      it "outputs glyph names as text" do
        output = capture_output do
          described_class.start(["glyphs", temp_font_file.path])
        end

        expect(output).to include("Glyph count: 4")
        expect(output).to include("Source: post_2.0")
        expect(output).to include("Glyph names:")
        expect(output).to include("0  .notdef")
        expect(output).to include("1  space")
        expect(output).to include("2  exclam")
        expect(output).to include("3  question")
      end
    end

    context "with yaml format" do
      it "outputs glyph information as YAML" do
        output = capture_output do
          described_class.start(["glyphs", temp_font_file.path, "--format",
                                 "yaml"])
        end

        expect(output).to include("glyph_count: 4")
        expect(output).to include("source: post_2.0")
        expect(output).to include("glyph_names:")
        expect(output).to include("- \".notdef\"")
        expect(output).to include("- space")
      end
    end

    context "with json format" do
      it "outputs glyph information as JSON" do
        output = capture_output do
          described_class.start(["glyphs", temp_font_file.path, "--format",
                                 "json"])
        end

        expect(output).to include('"glyph_count":4')
        expect(output).to include('"source":"post_2.0"')
        expect(output).to include('"glyph_names"')
        expect(output).to include('".notdef"')
        expect(output).to include('"space"')
      end
    end

    context "with quiet option" do
      it "suppresses output" do
        output = capture_output do
          described_class.start(["glyphs", temp_font_file.path, "--quiet"])
        end

        expect(output).to be_empty
      end
    end
  end

  describe "global options" do
    it "accepts font_index option" do
      expect do
        capture_output do
          described_class.start(["info", temp_font_file.path, "--font-index",
                                 "0"])
        end
      end.not_to raise_error
    end

    it "accepts font_index short option -i" do
      expect do
        capture_output do
          described_class.start(["info", temp_font_file.path, "-i", "0"])
        end
      end.not_to raise_error
    end

    it "accepts verbose option" do
      expect do
        capture_output do
          described_class.start(["info", temp_font_file.path, "--verbose"])
        end
      end.not_to raise_error
    end

    it "accepts verbose short option -v" do
      expect do
        capture_output do
          described_class.start(["info", temp_font_file.path, "-v"])
        end
      end.not_to raise_error
    end
  end

  private

  def capture_output
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  def capture_error
    old_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end

  def capture_output_and_error
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    { stdout: $stdout.string, stderr: $stderr.string }
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end
