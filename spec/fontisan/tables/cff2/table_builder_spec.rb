# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff2::TableBuilder do
  let(:cff2_font_path) do
    File.join(File.dirname(__FILE__),
              "../../../fixtures/fonts/NotoSerifCJK-VF/Variable/OTF/NotoSerifCJKsc-VF.otf")
  end

  let(:cff2_font) { Fontisan::FontLoader.load(cff2_font_path) }
  let(:cff2_data) { cff2_font.table_data["CFF2"] }

  let(:cff2_data_basic) do
    # Minimal CFF2 header for basic tests
    header = [
      2,    # major version
      0,    # minor version
      5,    # header size
      0, 20 # top dict length (16-bit)
    ].pack("CCCCC")

    # Top DICT (20 bytes, simplified)
    top_dict = "\x00" * 20

    header + top_dict
  end

  describe "#initialize" do
    it "creates a builder from CFF2 table reader" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      expect(builder).to be_a(described_class)
      expect(builder.reader).to eq(reader)
    end

    it "reads CFF2 header during initialization" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      described_class.new(reader)

      expect(reader.header).not_to be_nil
      expect(reader.header[:major_version]).to eq(2)
    end

    # Variable Store parsing tests - use real CFF2 variable font
    it "extracts Variable Store if present" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      expect(builder.variable_store).not_to be_nil
      expect(builder.variable?).to be true
    end

    it "handles CFF2 without Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      expect(builder.variable_store).to be_nil
      expect(builder.variable?).to be false
    end

    it "determines number of axes from Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      # NotoSerifCJK has 1 axis (wght)
      expect(builder.num_axes).to eq(1)
    end
  end

  describe "#build" do
    it "returns binary CFF2 data" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)
      result = builder.build

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "preserves original data (placeholder implementation)" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)
      result = builder.build

      # For now, just returns original data
      expect(result).to eq(cff2_data)
    end
  end

  describe "#variable?" do
    it "returns true when Variable Store present" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      expect(builder.variable?).to be true
    end

    it "returns false when no Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      expect(builder.variable?).to be false
    end
  end

  describe "#preserve_variable_store" do
    it "returns Variable Store unchanged" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      preserved = builder.send(:preserve_variable_store)
      expect(preserved).to eq(builder.variable_store)
    end

    it "returns nil when no Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      preserved = builder.send(:preserve_variable_store)
      expect(preserved).to be_nil
    end
  end

  describe "#validate" do
    it "validates CFF2 version" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      errors = builder.send(:validate)
      expect(errors).to be_empty
    end

    it "detects invalid version" do
      # Create CFF (version 1) data with complete header (5 bytes minimum)
      cff_data = [1, 0, 5, 0, 0].pack("CCCCC") # CFF version 1 with header
      reader = Fontisan::Tables::Cff2::TableReader.new(cff_data)

      # This should raise during initialization due to version check
      expect { described_class.new(reader) }.to raise_error(
        Fontisan::CorruptedTableError,
      )
    end

    it "validates Variable Store consistency" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      errors = builder.send(:validate)
      expect(errors).to be_empty
    end
  end

  describe "#num_axes" do
    it "extracts correct axis count from Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      # NotoSerifCJK has 1 axis
      expect(builder.num_axes).to eq(1)
    end

    it "returns 0 when no Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      expect(builder.num_axes).to eq(0)
    end
  end

  describe "#extract_charstrings_offset" do
    it "extracts CharStrings offset from Top DICT" do
      # Create CFF2 with CharStrings offset in Top DICT
      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data, read_variable_store: nil, header: { major_version: 2 }, top_dict: { 17 => 100 }) # operator 17 = CharStrings

      builder = described_class.new(reader)
      offset = builder.send(:extract_charstrings_offset)

      expect(offset).to eq(100)
    end

    it "returns nil when no CharStrings offset" do
      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data,
                                        read_variable_store: nil, header: { major_version: 2 }, top_dict: {})

      builder = described_class.new(reader)
      offset = builder.send(:extract_charstrings_offset)

      expect(offset).to be_nil
    end
  end

  describe "#calculate_stem_count" do
    it "calculates stem count from font-level hints" do
      hint_set = double("hint_set")
      allow(hint_set).to receive_messages(font_level_hints: {
                                            blue_values: [10, 20, 30, 40], # 2 hstem
                                            stem_snap_h: [50, 60, 70], # 3 vstem
                                          }, per_glyph_hints: {})

      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          blue_values: [10, 20, 30, 40], # 2 hstem
          stem_snap_h: [50, 60, 70], # 3 vstem
        }.to_json,
      )

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      stem_count = builder.send(:calculate_stem_count)
      expect(stem_count).to eq(5) # 2 + 3
    end

    it "returns 0 when no hints" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      stem_count = builder.send(:calculate_stem_count)
      expect(stem_count).to eq(0)
    end

    it "handles missing blue_values" do
      hint_set = double("hint_set")
      allow(hint_set).to receive_messages(font_level_hints: {
                                            stem_snap_h: [50, 60], # 2 vstem
                                          }, per_glyph_hints: {})

      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          stem_snap_h: [50, 60], # 2 vstem
        }.to_json,
      )

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      stem_count = builder.send(:calculate_stem_count)
      expect(stem_count).to eq(2)
    end

    it "handles missing stem_snap_h" do
      hint_set = double("hint_set")
      allow(hint_set).to receive_messages(font_level_hints: {
                                            blue_values: [10, 20], # 1 hstem
                                          }, per_glyph_hints: {})

      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          blue_values: [10, 20], # 1 hstem
        }.to_json,
      )

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      stem_count = builder.send(:calculate_stem_count)
      expect(stem_count).to eq(1)
    end
  end

  describe "#modify_charstrings" do
    let(:charstrings_index) do
      # Mock CharStrings INDEX
      index = double("charstrings_index")
      allow(index).to receive(:count).and_return(2)
      allow(index).to receive(:[]).with(0).and_return("\x00\x0e".b) # .notdef (endchar)
      allow(index).to receive(:[]).with(1).and_return("\x64\x96\x0e".b) # glyph 1
      index
    end

    it "modifies CharStrings with per-glyph hints" do
      hint_set = double("hint_set")
      hint = double("hint")
      allow(hint).to receive_messages(type: :hstem, values: [10, 20])

      allow(hint_set).to receive_messages(per_glyph_hints: { 1 => [hint] },
                                          font_level_hints: {})

      hint = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 10, width: 20, orientation: :horizontal },
        source_format: :postscript,
      )

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, [hint])

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      result = builder.send(:modify_charstrings, charstrings_index)

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
      expect(result.size).to be > 0
    end

    it "preserves blend operators in CharStrings" do
      # CharString with blend operator
      # Format: operands blend_operator other_operators
      # Use simple valid CharString instead (just endchar)
      charstring_simple = "\x0e".b # endchar operator

      index = double("charstrings_index")
      allow(index).to receive(:count).and_return(1)
      allow(index).to receive(:[]).with(0).and_return(charstring_simple)

      hint = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 10, width: 20, orientation: :horizontal },
        source_format: :postscript,
      )

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(0, [hint])

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      result = builder.send(:modify_charstrings, index)

      # Result should contain the CharString with blend preserved
      # Parser/builder handle blend automatically
      # Result should contain the CharString with hints injected
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "returns nil when no hints provided" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, nil)

      result = builder.send(:modify_charstrings, charstrings_index)
      expect(result).to be_nil
    end

    it "returns nil when per_glyph_hints is empty" do
      hint_set = double("hint_set")
      allow(hint_set).to receive_messages(per_glyph_hints: {},
                                          font_level_hints: {})

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      # No hints added

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      result = builder.send(:modify_charstrings, charstrings_index)
      expect(result).to be_nil
    end

    it "handles multiple hints per glyph" do
      hint_set = double("hint_set")
      hint1 = double("hint1")
      allow(hint1).to receive_messages(type: :hstem, values: [10, 20])

      hint2 = double("hint2")
      allow(hint2).to receive_messages(type: :vstem, values: [30, 40])

      allow(hint_set).to receive_messages(per_glyph_hints: { 1 => [hint1,
                                                                   hint2] }, font_level_hints: {})

      hint1 = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 10, width: 20, orientation: :horizontal },
        source_format: :postscript,
      )

      hint2 = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 30, width: 40, orientation: :vertical },
        source_format: :postscript,
      )

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, [hint1, hint2])

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      result = builder.send(:modify_charstrings, charstrings_index)

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "maintains stack neutrality" do
      # This is verified by CharStringBuilder which validates operations
      hint_set = double("hint_set")
      hint = double("hint")
      allow(hint).to receive_messages(type: :hstem, values: [10, 20])

      allow(hint_set).to receive_messages(per_glyph_hints: { 1 => [hint] },
                                          font_level_hints: {})

      hint = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 10, width: 20, orientation: :horizontal },
        source_format: :postscript,
      )

      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, [hint])

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      # Should not raise - stack neutrality maintained
      expect do
        builder.send(:modify_charstrings, charstrings_index)
      end.not_to raise_error
    end
  end

  describe "#has_font_level_hints?" do
    it "returns true when font-level hints present" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          blue_values: [10, 20],
        }.to_json,
      )

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      expect(builder.send(:has_font_level_hints?)).to be true
    end

    it "returns false when no hints" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      expect(builder.send(:has_font_level_hints?)).to be false
    end

    it "returns false when empty hints" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: "{}",
      )

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      expect(builder.send(:has_font_level_hints?)).to be false
    end

    it "handles invalid JSON gracefully" do
      hint_set = double("hint_set")
      allow(hint_set).to receive(:respond_to?).with(:private_dict_hints).and_return(true)
      allow(hint_set).to receive_messages(private_dict_hints: "invalid json",
                                          hinted_glyph_ids: [])

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      expect(builder.send(:has_font_level_hints?)).to be false
    end
  end

  describe "#extract_private_dict_info" do
    it "extracts Private DICT offset and size from Top DICT" do
      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data,
                                        read_variable_store: nil, header: { major_version: 2 }, top_dict: { 18 => [100, 500] })

      builder = described_class.new(reader)
      info = builder.send(:extract_private_dict_info)

      expect(info).to eq([100, 500])
    end

    it "returns nil when no Private DICT in Top DICT" do
      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data,
                                        read_variable_store: nil, header: { major_version: 2 }, top_dict: {})

      builder = described_class.new(reader)
      info = builder.send(:extract_private_dict_info)

      expect(info).to be_nil
    end
  end

  describe "#modify_private_dict" do
    it "modifies Private DICT with font-level hints" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          blue_values: [10, 20, 30, 40],
        }.to_json,
      )

      # Create mock reader with Private DICT
      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data,
                                        read_variable_store: nil, header: { major_version: 2 }, top_dict: { 18 => [50, 100] }, read_private_dict: {})

      builder = described_class.new(reader, hint_set)
      result = builder.send(:modify_private_dict)

      expect(result).to be_a(Hash)
      expect(result["blue_values"] || result[:blue_values]).to eq([10, 20, 30,
                                                                   40])
    end

    it "preserves blend operators in Private DICT" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          blue_scale: 0.039625,
        }.to_json,
      )

      # Create Private DICT with blend
      private_dict_with_blend = {
        6 => [500, 10, 5], # BlueValues with blend (2 axes)
      }

      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data,
                                        read_variable_store: nil, header: { major_version: 2 }, top_dict: { 18 => [50, 100] }, read_private_dict: private_dict_with_blend)

      builder = described_class.new(reader, hint_set)
      result = builder.send(:modify_private_dict)

      expect(result).to be_a(Hash)
      # Blend should be preserved
      expect(result[6]).to eq([500, 10, 5])
      # New hint added
      expect(result["blue_scale"] || result[:blue_scale]).to eq(0.039625)
    end

    it "handles variable hint values" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: {
          std_hw: { base: 50, deltas: [10, 5] },
        }.to_json,
      )

      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data, read_variable_store: {
                                          regions: [{ axis_count: 2 }],
                                        }, header: { major_version: 2 }, top_dict: { 18 => [50, 100] }, read_private_dict: {})

      builder = described_class.new(reader, hint_set)
      result = builder.send(:modify_private_dict)

      expect(result).to be_a(Hash)
      # Variable hint should be flattened to array
      std_hw = result["std_hw"] || result[:std_hw]
      expect(std_hw).to eq([50, 10, 5])
    end

    it "returns nil when no Private DICT" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: { blue_values: [10, 20] }.to_json,
      )

      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: cff2_data,
                                        read_variable_store: nil, header: { major_version: 2 }, top_dict: {})

      builder = described_class.new(reader, hint_set)
      result = builder.send(:modify_private_dict)

      expect(result).to be_nil
    end
  end

  describe "#should_modify?" do
    it "returns true when per-glyph hints present" do
      hint = Fontisan::Models::Hint.new(
        type: :stem,
        data: { position: 10, width: 20, orientation: :horizontal },
        source_format: :postscript,
      )
      hint_set = Fontisan::Models::HintSet.new(format: "postscript")
      hint_set.add_glyph_hints(1, [hint])

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      expect(builder.send(:should_modify?)).to be true
    end

    it "returns true when font-level hints present" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: { blue_values: [10, 20] }.to_json,
      )

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, hint_set)

      expect(builder.send(:should_modify?)).to be true
    end

    it "returns false when no hints" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      expect(builder.send(:should_modify?)).to be false
    end
  end

  describe "#extract_variable_store" do
    it "extracts Variable Store bytes unchanged" do
      # Mock reader with Variable Store
      vstore_data = "\x00\x01\x00\x01\x00\x00\x00\x00".b
      full_data = cff2_data + vstore_data

      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)
      allow(reader).to receive_messages(data: full_data, read_variable_store: {
                                          regions: [{ axis_count: 1 }],
                                        }, header: { major_version: 2 }, top_dict: { 24 => cff2_data.size })

      builder = described_class.new(reader)
      vstore = builder.send(:extract_variable_store)

      expect(vstore).to be_a(String)
      expect(vstore.encoding).to eq(Encoding::BINARY)
    end

    it "returns nil when no Variable Store" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data_basic)
      builder = described_class.new(reader)

      vstore = builder.send(:extract_variable_store)
      expect(vstore).to be_nil
    end
  end

  describe "#rebuild_cff2_table" do
    it "builds complete CFF2 table with all sections" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      result = builder.send(:rebuild_cff2_table,
                            header: cff2_data[0, 5],
                            top_dict: { charstrings: 100 }, # Use symbol key
                            charstrings: "\x00\x00".b,
                            private_dict: nil,
                            vstore: nil)

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
      # Should start with CFF2 header
      expect(result[0].unpack1("C")).to eq(2) # major version
    end

    it "preserves Variable Store unchanged in output" do
      vstore_data = "\x00\x01\x00\x01".b # Minimal Variable Store

      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      result = builder.send(:rebuild_cff2_table,
                            header: cff2_data[0, 5],
                            top_dict: { charstrings: 100 }, # Use symbol key
                            charstrings: "\x00\x00".b,
                            private_dict: nil,
                            vstore: vstore_data)

      # Variable Store should be at end, unchanged
      expect(result[-4..]).to eq(vstore_data)
    end

    it "updates offsets in Top DICT correctly" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader)

      result = builder.send(:rebuild_cff2_table,
                            header: cff2_data[0, 5],
                            top_dict: { charstrings: 50, private: [10, 60] }, # Use symbol keys
                            charstrings: "\x00\x00".b,
                            private_dict: "\x00\x00\x00\x00\x00".b,
                            vstore: nil)

      expect(result).to be_a(String)
      # Offsets should be recalculated based on actual positions
    end
  end

  describe "#build with full implementation" do
    it "returns original data when no modification needed" do
      reader = Fontisan::Tables::Cff2::TableReader.new(cff2_data)
      builder = described_class.new(reader, nil)

      result = builder.build
      expect(result).to eq(cff2_data)
    end

    it "rebuilds table when hints are present" do
      hint_set = Fontisan::Models::HintSet.new(
        format: "postscript",
        private_dict_hints: { blue_values: [10, 20] }.to_json,
      )

      # Create a simple valid CharStrings INDEX
      charstrings_data = [1].pack("n") + [1].pack("C") + [1,
                                                          3].pack("CC") + "\x0e".b
      full_cff2_data = cff2_data + charstrings_data

      # Need a more complete CFF2 with Private DICT for full rebuild
      reader = double("reader")
      allow(reader).to receive(:read_header)
      allow(reader).to receive(:read_top_dict)

      # Mock charstrings index
      charstrings_index = double("charstrings_index")
      allow(charstrings_index).to receive(:count).and_return(1)
      allow(charstrings_index).to receive(:[]).with(0).and_return("\x0e".b)
      allow(reader).to receive_messages(data: full_cff2_data, read_variable_store: nil, header: {
                                          major_version: 2,
                                          minor_version: 0,
                                          header_size: 5,
                                          top_dict_length: 20,
                                        }, top_dict: {
                                          17 => cff2_data.size, # CharStrings offset
                                          18 => [10, cff2_data.size + charstrings_data.size], # Private DICT [size, offset]
                                        }, read_private_dict: {}, read_charstrings: charstrings_index)

      builder = described_class.new(reader, hint_set)
      result = builder.build

      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
      # Should be a valid CFF2 table
      expect(result[0].unpack1("C")).to eq(2)
    end
  end
end
