# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::Cff::CharStringRebuilder do
  # Helper to create a mock CharStrings INDEX
  def create_mock_index(charstrings_data)
    # Build CharStrings INDEX from array of CharString binary data
    Fontisan::Tables::Cff::IndexBuilder.build(charstrings_data)
  end

  # Helper to parse INDEX back to array
  def parse_index(index_data)
    io = StringIO.new(index_data)
    index = Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    (0...index.count).map { |i| index[i] }
  end

  describe "#initialize" do
    it "creates rebuilder with CharStrings INDEX" do
      charstrings = [
        [14].pack("C"), # .notdef: endchar
        [239, 22, 14].pack("C*") # glyph 1: 100 hmoveto endchar
      ]
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      index = Fontisan::Tables::Cff::Index.new(io, start_offset: 0)

      rebuilder = described_class.new(index)
      expect(rebuilder.source_index).to eq(index)
    end

    it "accepts stem_count parameter" do
      charstrings = [[14].pack("C")]
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      index = Fontisan::Tables::Cff::Index.new(io, start_offset: 0)

      rebuilder = described_class.new(index, stem_count: 8)
      expect(rebuilder).to be_a(described_class)
    end
  end

  describe "#modify_charstring" do
    let(:charstrings) do
      [
        [14].pack("C"), # .notdef: endchar
        [239, 22, 14].pack("C*"), # glyph 1: 100 hmoveto endchar
        [200, 4, 14].pack("C*") # glyph 2: 61 vmoveto endchar
      ]
    end

    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end

    let(:rebuilder) { described_class.new(index) }

    it "modifies a single CharString" do
      rebuilder.modify_charstring(1) do |operations|
        # Add vstem hint before existing operations
        hint = { type: :operator, name: :vstem, operands: [10, 20] }
        [hint] + operations
      end

      expect(rebuilder.modified?(1)).to be true
      expect(rebuilder.modified?(0)).to be false
      expect(rebuilder.modified?(2)).to be false
    end

    it "stores modified CharString data" do
      rebuilder.modify_charstring(1) do |operations|
        operations # Return unchanged
      end

      data = rebuilder.charstring_data(1)
      expect(data).to be_a(String)
      expect(data.encoding).to eq(Encoding::BINARY)
    end

    it "allows appending operations" do
      rebuilder.modify_charstring(1) do |operations|
        # Insert rlineto before endchar
        endchar = operations.pop
        operations << { type: :operator, name: :rlineto, operands: [50, 100] }
        operations << endchar
        operations
      end

      expect(rebuilder.modified?(1)).to be true
    end

    it "allows removing operations" do
      rebuilder.modify_charstring(1) do |operations|
        # Keep only endchar
        operations.select { |op| op[:name] == :endchar }
      end

      expect(rebuilder.modified?(1)).to be true
    end

    it "handles invalid glyph index gracefully" do
      expect {
        rebuilder.modify_charstring(999) { |ops| ops }
      }.not_to raise_error
    end
  end

  describe "#rebuild" do
    let(:charstrings) do
      [
        [14].pack("C"), # .notdef
        [239, 22, 14].pack("C*"), # glyph 1
        [200, 4, 14].pack("C*") # glyph 2
      ]
    end

    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end

    let(:rebuilder) { described_class.new(index) }

    it "rebuilds INDEX with no modifications" do
      new_index_data = rebuilder.rebuild

      # Should have same structure
      expect(new_index_data).to be_a(String)
      expect(new_index_data.encoding).to eq(Encoding::BINARY)

      # Parse and verify count
      new_charstrings = parse_index(new_index_data)
      expect(new_charstrings.length).to eq(3)
    end

    it "rebuilds INDEX with one modified CharString" do
      rebuilder.modify_charstring(1) do |operations|
        # Add hint
        hint = { type: :operator, name: :hstem, operands: [10, 20] }
        [hint] + operations
      end

      new_index_data = rebuilder.rebuild
      new_charstrings = parse_index(new_index_data)

      # All three CharStrings should be present
      expect(new_charstrings.length).to eq(3)

      # Glyph 1 should be modified (longer than original)
      expect(new_charstrings[1].bytesize).to be > charstrings[1].bytesize

      # Others unchanged
      expect(new_charstrings[0]).to eq(charstrings[0])
      expect(new_charstrings[2]).to eq(charstrings[2])
    end

    it "rebuilds INDEX with multiple modifications" do
      rebuilder.modify_charstring(1) { |ops| ops } # Modify glyph 1
      rebuilder.modify_charstring(2) { |ops| ops } # Modify glyph 2

      new_index_data = rebuilder.rebuild
      new_charstrings = parse_index(new_index_data)

      expect(new_charstrings.length).to eq(3)
      expect(rebuilder.modification_count).to eq(2)
    end

    it "produces valid INDEX structure" do
      rebuilder.modify_charstring(1) do |operations|
        operations # No actual change
      end

      new_index_data = rebuilder.rebuild

      # Should be parseable
      io = StringIO.new(new_index_data)
      new_index = Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
      expect(new_index.count).to eq(3)
    end
  end

  describe "#batch_modify" do
    let(:charstrings) do
      [
        [14].pack("C"), # .notdef
        [239, 22, 14].pack("C*"), # glyph 1
        [200, 4, 14].pack("C*"), # glyph 2
        [139, 21, 14].pack("C*") # glyph 3: 0,0 rmoveto endchar
      ]
    end

    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end

    let(:rebuilder) { described_class.new(index) }

    it "modifies multiple glyphs at once" do
      rebuilder.batch_modify([1, 2, 3]) do |glyph_index, operations|
        # Add hstem to each
        hint = { type: :operator, name: :hstem, operands: [glyph_index * 10, 20] }
        [hint] + operations
      end

      expect(rebuilder.modification_count).to eq(3)
      expect(rebuilder.modified?(1)).to be true
      expect(rebuilder.modified?(2)).to be true
      expect(rebuilder.modified?(3)).to be true
    end

    it "allows glyph-specific modifications" do
      rebuilder.batch_modify([1, 2]) do |glyph_index, operations|
        if glyph_index == 1
          # Different modification for glyph 1
          operations
        else
          # Different modification for glyph 2
          operations
        end
      end

      expect(rebuilder.modification_count).to eq(2)
    end
  end

  describe "#modify_all" do
    let(:charstrings) do
      [
        [14].pack("C"),
        [239, 22, 14].pack("C*"),
        [200, 4, 14].pack("C*")
      ]
    end

    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end

    let(:rebuilder) { described_class.new(index) }

    it "modifies all CharStrings" do
      rebuilder.modify_all do |glyph_index, operations|
        # Add comment (no-op for CharStrings but tests the mechanism)
        operations
      end

      expect(rebuilder.modification_count).to eq(3)
      expect(rebuilder.modified?(0)).to be true
      expect(rebuilder.modified?(1)).to be true
      expect(rebuilder.modified?(2)).to be true
    end

    it "allows index-specific modifications" do
      rebuilder.modify_all do |glyph_index, operations|
        if glyph_index == 0
          # Skip .notdef
          operations
        else
          # Add hint to others
          hint = { type: :operator, name: :vstem, operands: [10, 20] }
          [hint] + operations
        end
      end

      new_index_data = rebuilder.rebuild
      new_charstrings = parse_index(new_index_data)

      # .notdef should be same size
      expect(new_charstrings[0].bytesize).to eq(charstrings[0].bytesize)
      # Others should be larger
      expect(new_charstrings[1].bytesize).to be > charstrings[1].bytesize
    end
  end

  describe "#charstring_data" do
    let(:charstrings) do
      [
        [14].pack("C"),
        [239, 22, 14].pack("C*")
      ]
    end

    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end

    let(:rebuilder) { described_class.new(index) }

    it "returns original data for unmodified glyph" do
      data = rebuilder.charstring_data(0)
      expect(data).to eq(charstrings[0])
    end

    it "returns modified data for modified glyph" do
      rebuilder.modify_charstring(1) { |ops| ops }
      data = rebuilder.charstring_data(1)
      expect(data).not_to be_nil
      expect(data.encoding).to eq(Encoding::BINARY)
    end
  end

  describe "#modified?" do
    let(:charstrings) { [[14].pack("C"), [239, 22, 14].pack("C*")] }
    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end
    let(:rebuilder) { described_class.new(index) }

    it "returns false for unmodified glyph" do
      expect(rebuilder.modified?(0)).to be false
    end

    it "returns true for modified glyph" do
      rebuilder.modify_charstring(1) { |ops| ops }
      expect(rebuilder.modified?(1)).to be true
    end
  end

  describe "#modification_count" do
    let(:charstrings) do
      [
        [14].pack("C"),
        [239, 22, 14].pack("C*"),
        [200, 4, 14].pack("C*")
      ]
    end

    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end

    let(:rebuilder) { described_class.new(index) }

    it "returns 0 initially" do
      expect(rebuilder.modification_count).to eq(0)
    end

    it "increments with each modification" do
      rebuilder.modify_charstring(0) { |ops| ops }
      expect(rebuilder.modification_count).to eq(1)

      rebuilder.modify_charstring(1) { |ops| ops }
      expect(rebuilder.modification_count).to eq(2)
    end
  end

  describe "#clear_modifications" do
    let(:charstrings) { [[14].pack("C"), [239, 22, 14].pack("C*")] }
    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end
    let(:rebuilder) { described_class.new(index) }

    it "clears all modifications" do
      rebuilder.modify_charstring(0) { |ops| ops }
      rebuilder.modify_charstring(1) { |ops| ops }
      expect(rebuilder.modification_count).to eq(2)

      rebuilder.clear_modifications
      expect(rebuilder.modification_count).to eq(0)
      expect(rebuilder.modified?(0)).to be false
      expect(rebuilder.modified?(1)).to be false
    end
  end

  describe "#stem_count=" do
    let(:charstrings) { [[14].pack("C")] }
    let(:index) do
      index_data = create_mock_index(charstrings)
      io = StringIO.new(index_data)
      Fontisan::Tables::Cff::Index.new(io, start_offset: 0)
    end
    let(:rebuilder) { described_class.new(index, stem_count: 0) }

    it "updates stem count" do
      rebuilder.stem_count = 8
      # Verify it works (implicitly through successful modification)
      expect {
        rebuilder.modify_charstring(0) { |ops| ops }
      }.not_to raise_error
    end
  end
end