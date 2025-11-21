# frozen_string_literal: true

require "spec_helper"
require "fontisan/variable/table_updater"

RSpec.describe Fontisan::Variable::TableUpdater do
  let(:updater) { described_class.new }

  describe "#update_hmtx" do
    it "updates hmtx table with varied metrics" do
      # Build original hmtx with 2 glyphs
      original_hmtx = String.new(encoding: Encoding::BINARY)
      original_hmtx << [500].pack("n")  # glyph 0 advance width
      original_hmtx << [50].pack("n")   # glyph 0 lsb (signed as unsigned)
      original_hmtx << [600].pack("n")  # glyph 1 advance width
      original_hmtx << [60].pack("n")   # glyph 1 lsb

      # Vary glyph 0
      varied_metrics = {
        0 => { advance_width: 550, lsb: 55 },
      }

      result = updater.update_hmtx(original_hmtx, varied_metrics, 2, 2)

      # Parse result
      io = StringIO.new(result)
      io.set_encoding(Encoding::BINARY)

      advance0 = io.read(2).unpack1("n")
      lsb0 = io.read(2).unpack1("n")
      lsb0 = lsb0 >= 0x8000 ? lsb0 - 0x10000 : lsb0

      advance1 = io.read(2).unpack1("n")
      lsb1 = io.read(2).unpack1("n")
      lsb1 = lsb1 >= 0x8000 ? lsb1 - 0x10000 : lsb1

      expect(advance0).to eq(550)
      expect(lsb0).to eq(55)
      expect(advance1).to eq(600)
      expect(lsb1).to eq(60)
    end

    it "handles negative LSB values" do
      # Build original hmtx
      original_hmtx = String.new(encoding: Encoding::BINARY)
      original_hmtx << [500].pack("n")
      original_hmtx << [0xFFCE].pack("n") # -50 as unsigned

      varied_metrics = {
        0 => { advance_width: 500, lsb: -100 },
      }

      result = updater.update_hmtx(original_hmtx, varied_metrics, 1, 1)

      io = StringIO.new(result)
      io.set_encoding(Encoding::BINARY)
      io.read(2) # skip advance
      lsb = io.read(2).unpack1("n")
      lsb = lsb >= 0x8000 ? lsb - 0x10000 : lsb

      expect(lsb).to eq(-100)
    end

    it "updates glyphs beyond numberOfHMetrics" do
      # Build hmtx with 1 hMetric + 1 LSB
      original_hmtx = String.new(encoding: Encoding::BINARY)
      original_hmtx << [500].pack("n")   # advance width
      original_hmtx << [50].pack("n")    # lsb for glyph 0
      original_hmtx << [60].pack("n")    # lsb for glyph 1

      # Vary glyph 1 (uses last advance width)
      varied_metrics = {
        1 => { lsb: 75 },
      }

      result = updater.update_hmtx(original_hmtx, varied_metrics, 1, 2)

      io = StringIO.new(result)
      io.set_encoding(Encoding::BINARY)
      io.read(4) # skip first hMetric
      lsb1 = io.read(2).unpack1("n")

      expect(lsb1).to eq(75)
    end
  end

  describe "#update_hhea" do
    it "updates hhea table with varied metrics" do
      # Build original hhea (36 bytes)
      original_hhea = String.new(encoding: Encoding::BINARY)
      original_hhea << [0x00010000].pack("N")  # version
      original_hhea << [2048].pack("n")        # ascent (signed as unsigned)
      original_hhea << [0xFE00].pack("n")      # descent (-512 as unsigned)
      original_hhea << [0].pack("n")           # line_gap
      original_hhea << "\x00" * 26             # rest of table

      varied_metrics = {
        ascent: 2100,
        descent: -550,
        line_gap: 100,
      }

      result = updater.update_hhea(original_hhea, varied_metrics)

      io = StringIO.new(result)
      io.set_encoding(Encoding::BINARY)
      io.read(4) # skip version

      ascent = io.read(2).unpack1("n")
      ascent = ascent >= 0x8000 ? ascent - 0x10000 : ascent

      descent = io.read(2).unpack1("n")
      descent = descent >= 0x8000 ? descent - 0x10000 : descent

      line_gap = io.read(2).unpack1("n")

      expect(ascent).to eq(2100)
      expect(descent).to eq(-550)
      expect(line_gap).to eq(100)
    end

    it "preserves rest of hhea table" do
      original_hhea = String.new(encoding: Encoding::BINARY)
      original_hhea << [0x00010000].pack("N")
      original_hhea << [2048, 0xFE00, 0].pack("n3")
      original_hhea << [1000].pack("n") # advance_width_max
      rest_data = "\xFF" * 22
      rest_data.force_encoding(Encoding::BINARY)
      original_hhea << rest_data

      varied_metrics = { ascent: 2100 }

      result = updater.update_hhea(original_hhea, varied_metrics)

      # Check that rest of table is preserved
      expect(result[10, 2]).to eq([1000].pack("n"))
      expect(result[12, 22]).to eq(rest_data)
    end
  end

  describe "#update_head_modified" do
    it "updates head table modified timestamp" do
      # Build minimal head table (54 bytes)
      original_head = String.new(encoding: Encoding::BINARY)
      original_head << "\x00" * 28 # up to created timestamp
      original_head << [0].pack("q>") # old modified (8 bytes)
      original_head << "\x00" * 18 # rest of table

      timestamp = Time.new(2024, 1, 1, 0, 0, 0, "+00:00")
      result = updater.update_head_modified(original_head, timestamp)

      # Parse modified timestamp
      io = StringIO.new(result)
      io.read(28) # skip to modified
      modified_raw = io.read(8).unpack1("q>")

      # Convert back to Time
      expected_longdatetime = timestamp.to_i + 2_082_844_800
      expect(modified_raw).to eq(expected_longdatetime)
    end

    it "preserves rest of head table" do
      original_head = String.new(encoding: Encoding::BINARY)
      header_data = "\x01" * 28
      original_head << header_data
      original_head << [0].pack("q>")
      footer_data = "\x02" * 18
      original_head << footer_data

      result = updater.update_head_modified(original_head)

      expect(result[0, 28]).to eq(header_data)
      expect(result[36, 18]).to eq(footer_data)
    end
  end

  describe "#apply_updates" do
    it "applies updates at specific offsets" do
      original = "ABCDEFGHIJ"
      updates = {
        0 => "X",
        5 => "Y",
      }

      result = updater.apply_updates(original, updates)

      expect(result).to eq("XBCDEYGHIJ")
    end

    it "handles integer values" do
      original = "\x00" * 10
      updates = {
        0 => 100,
        4 => 200,
      }

      result = updater.apply_updates(original, updates)

      expect(result[0, 2].unpack1("n")).to eq(100)
      expect(result[4, 2].unpack1("n")).to eq(200)
    end
  end
end
