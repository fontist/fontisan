# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::GlyphsCommand do
  # Helper to build post table version 1.0
  def build_post_table_v1
    version = [0x00010000].pack("N") # Version 1.0
    italic_angle = [0].pack("N")
    underline_position = [0].pack("n")
    underline_thickness = [0].pack("n")
    is_fixed_pitch = [0].pack("N")
    min_mem_type42 = [0].pack("N")
    max_mem_type42 = [0].pack("N")
    min_mem_type1 = [0].pack("N")
    max_mem_type1 = [0].pack("N")

    version + italic_angle + underline_position + underline_thickness +
      is_fixed_pitch + min_mem_type42 + max_mem_type42 +
      min_mem_type1 + max_mem_type1
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

  # Helper to build post table version 3.0
  def build_post_table_v3
    version = [0x00030000].pack("N") # Version 3.0
    italic_angle = [0].pack("N")
    underline_position = [0].pack("n")
    underline_thickness = [0].pack("n")
    is_fixed_pitch = [0].pack("N")
    min_mem_type42 = [0].pack("N")
    max_mem_type42 = [0].pack("N")
    min_mem_type1 = [0].pack("N")
    max_mem_type1 = [0].pack("N")

    version + italic_angle + underline_position + underline_thickness +
      is_fixed_pitch + min_mem_type42 + max_mem_type42 +
      min_mem_type1 + max_mem_type1
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
    context "with post version 1.0" do
      let(:font_data) { build_font_data("post" => build_post_table_v1) }

      it "returns a GlyphInfo instance" do
        result = command.run
        expect(result).to be_a(Fontisan::Models::GlyphInfo)
      end

      it "returns 258 standard glyph names" do
        result = command.run
        expect(result.glyph_count).to eq(258)
        expect(result.glyph_names.length).to eq(258)
      end

      it "returns correct standard names" do
        result = command.run
        expect(result.glyph_names[0]).to eq(".notdef")
        expect(result.glyph_names[1]).to eq(".null")
        expect(result.glyph_names[2]).to eq("nonmarkingreturn")
        expect(result.glyph_names[3]).to eq("space")
      end

      it "sets source to post_1.0" do
        result = command.run
        expect(result.source).to eq("post_1.0")
      end
    end

    context "with post version 2.0" do
      let(:custom_names) do
        [".notdef", "space", "customGlyph1", "customGlyph2"]
      end
      let(:font_data) do
        build_font_data("post" => build_post_table_v2(custom_names))
      end

      it "returns custom glyph names" do
        result = command.run
        expect(result.glyph_count).to eq(4)
        expect(result.glyph_names).to eq(custom_names)
      end

      it "sets source to post_2.0" do
        result = command.run
        expect(result.source).to eq("post_2.0")
      end
    end

    context "with post version 3.0" do
      let(:font_data) { build_font_data("post" => build_post_table_v3) }

      it "returns no glyph names" do
        result = command.run
        expect(result.glyph_count).to eq(0)
        expect(result.glyph_names).to be_empty
      end

      it "sets source to none" do
        result = command.run
        expect(result.source).to eq("none")
      end
    end

    context "without post table" do
      let(:font_data) { build_font_data }

      it "returns no glyph names" do
        result = command.run
        expect(result.glyph_count).to eq(0)
        expect(result.glyph_names).to be_empty
      end

      it "sets source to none" do
        result = command.run
        expect(result.source).to eq("none")
      end
    end
  end
end
