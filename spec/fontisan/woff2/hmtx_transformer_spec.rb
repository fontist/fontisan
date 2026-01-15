# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::HmtxTransformer do
  describe ".read_255_uint16" do
    it "reads single-byte values (< 253)" do
      io = StringIO.new([100].pack("C"))
      expect(described_class.send(:read_255_uint16, io)).to eq(100)
    end

    it "reads code 253 format (253 + uint16)" do
      io = StringIO.new([253, 100].pack("Cn"))
      expect(described_class.send(:read_255_uint16, io)).to eq(353)  # 253 + 100
    end

    it "reads code 254 format (506 + uint16)" do
      io = StringIO.new([254, 100].pack("Cn"))
      expect(described_class.send(:read_255_uint16, io)).to eq(606)  # 253*2 + 100
    end

    it "reads code 255 format (759 + uint16)" do
      io = StringIO.new([255, 100].pack("Cn"))
      expect(described_class.send(:read_255_uint16, io)).to eq(859)  # 253*3 + 100
    end

    it "handles maximum single-byte value (252)" do
      io = StringIO.new([252].pack("C"))
      expect(described_class.send(:read_255_uint16, io)).to eq(252)
    end
  end

  describe ".build_hmtx_table" do
    it "builds standard hmtx table with full metrics" do
      advance_widths = [500, 600, 700]
      lsbs = [50, 60, 70]
      num_h_metrics = 3
      num_glyphs = 3

      result = described_class.send(:build_hmtx_table, advance_widths, lsbs,
                                    num_h_metrics, num_glyphs)

      expect(result).to be_a(String)

      # Parse result
      io = StringIO.new(result)

      # Read longHorMetric entries
      3.times do |i|
        advance = io.read(2).unpack1("n")
        lsb = io.read(2).unpack1("n")

        expect(advance).to eq(advance_widths[i])
        # LSB is stored as signed int16
        lsb_signed = lsb > 0x7FFF ? lsb - 0x10000 : lsb
        expect(lsb_signed).to eq(lsbs[i])
      end
    end

    it "builds hmtx table with additional LSBs" do
      advance_widths = [500, 600]
      lsbs = [50, 60, 70, 80] # Extra LSBs
      num_h_metrics = 2
      num_glyphs = 4

      result = described_class.send(:build_hmtx_table, advance_widths, lsbs,
                                    num_h_metrics, num_glyphs)

      io = StringIO.new(result)

      # Read longHorMetric entries
      2.times do |i|
        advance = io.read(2).unpack1("n")
        io.read(2).unpack1("n")
        expect(advance).to eq(advance_widths[i])
      end

      # Read additional LSBs
      2.times do |i|
        lsb = io.read(2).unpack1("n")
        lsb_signed = lsb > 0x7FFF ? lsb - 0x10000 : lsb
        expect(lsb_signed).to eq(lsbs[i + 2])
      end
    end

    it "handles glyphs sharing last advance width" do
      advance_widths = [500]
      lsbs = [50, 60, 70] # 3 glyphs
      num_h_metrics = 1
      num_glyphs = 3

      result = described_class.send(:build_hmtx_table, advance_widths, lsbs,
                                    num_h_metrics, num_glyphs)

      io = StringIO.new(result)

      # First entry has both advance and LSB
      advance = io.read(2).unpack1("n")
      lsb = io.read(2).unpack1("n")
      expect(advance).to eq(500)

      # Remaining glyphs only have LSBs
      2.times do |i|
        lsb = io.read(2).unpack1("n")
        lsb_signed = lsb > 0x7FFF ? lsb - 0x10000 : lsb
        expect(lsb_signed).to eq(lsbs[i + 1])
      end
    end

    it "handles missing lsb values gracefully" do
      advance_widths = [500, 600]
      lsbs = [50] # Only one LSB
      num_h_metrics = 2
      num_glyphs = 2

      result = described_class.send(:build_hmtx_table, advance_widths, lsbs,
                                    num_h_metrics, num_glyphs)

      io = StringIO.new(result)

      # First entry
      advance = io.read(2).unpack1("n")
      io.read(2).unpack1("n")
      expect(advance).to eq(500)

      # Second entry - missing LSB defaults to 0
      advance = io.read(2).unpack1("n")
      lsb = io.read(2).unpack1("n")
      expect(advance).to eq(600)
      expect(lsb).to eq(0)
    end
  end

  describe ".reconstruct" do
    context "with explicit advance widths" do
      it "reconstructs hmtx table from explicit advance widths" do
        # Build transformed data with explicit advance widths flag
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_ADVANCE_WIDTHS |
          described_class::HMTX_FLAG_EXPLICIT_LSB_VALUES
        data << [flags].pack("C")

        # Advance widths (255UInt16 format)
        data << [100, 110, 120].pack("C3") # Three advance widths

        # LSB values (int16)
        data << [10, 20, 30].pack("n3")

        result = described_class.reconstruct(data, 3, 3, nil)

        expect(result).to be_a(String)

        # Verify structure
        io = StringIO.new(result)
        3.times do |i|
          advance = io.read(2).unpack1("n")
          lsb = io.read(2).unpack1("n")

          expect(advance).to eq(100 + (i * 10))
          lsb_signed = lsb > 0x7FFF ? lsb - 0x10000 : lsb
          expect(lsb_signed).to eq(10 + (i * 10))
        end
      end
    end

    context "with proportional encoding" do
      it "reconstructs hmtx table from delta encoding" do
        # Build transformed data with proportional encoding (no explicit flag)
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_LSB_VALUES
        data << [flags].pack("C")

        # First advance width explicit, then deltas
        data << [100].pack("C") # First advance width
        data << [10, -5].pack("n2") # Deltas: +10, -5

        # LSB values
        data << [10, 20, 30].pack("n3")

        result = described_class.reconstruct(data, 3, 3, nil)

        io = StringIO.new(result)

        # First glyph: advance=100
        advance = io.read(2).unpack1("n")
        expect(advance).to eq(100)
        io.read(2) # Skip LSB

        # Second glyph: advance=100+10=110
        advance = io.read(2).unpack1("n")
        expect(advance).to eq(110)
        io.read(2) # Skip LSB

        # Third glyph: advance=110-5=105
        advance = io.read(2).unpack1("n")
        expect(advance).to eq(105)
      end
    end

    context "with glyf-derived LSBs" do
      it "uses LSBs from glyf bounding boxes" do
        # Build transformed data without explicit LSBs
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_ADVANCE_WIDTHS
        data << [flags].pack("C")

        # Advance widths
        data << [100, 110, 120].pack("C3")

        # Provide LSBs from glyf
        glyf_lsbs = [15, 25, 35]

        result = described_class.reconstruct(data, 3, 3, glyf_lsbs)

        io = StringIO.new(result)

        # Verify LSBs match glyf-derived values
        3.times do |i|
          io.read(2) # Skip advance width
          lsb = io.read(2).unpack1("n")
          lsb_signed = lsb > 0x7FFF ? lsb - 0x10000 : lsb
          expect(lsb_signed).to eq(glyf_lsbs[i])
        end
      end

      it "falls back to reading LSBs when glyf_lsbs not provided" do
        # Build transformed data without flags
        data = +""
        flags = 0 # No flags
        data << [flags].pack("C")

        # First advance width and delta
        data << [100, 10].pack("Cn")

        # LSB values for both glyphs
        data << [20, 30].pack("n2")

        result = described_class.reconstruct(data, 2, 2, nil)

        io = StringIO.new(result)

        # Verify structure
        2.times do |_i|
          advance = io.read(2).unpack1("n")
          lsb = io.read(2).unpack1("n")
          expect(advance).to be > 0
          expect(lsb).to be >= 0
        end
      end
    end

    context "with additional LSBs for monospaced glyphs" do
      it "handles glyphs sharing last advance width" do
        # Build transformed data
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_ADVANCE_WIDTHS |
          described_class::HMTX_FLAG_EXPLICIT_LSB_VALUES
        data << [flags].pack("C")

        # Only one advance width (for 5 glyphs total)
        data << [100].pack("C")

        # LSBs for all 5 glyphs
        data << [10, 20, 30, 40, 50].pack("n5")

        result = described_class.reconstruct(data, 5, 1, nil)

        io = StringIO.new(result)

        # First glyph has full metric
        advance = io.read(2).unpack1("n")
        lsb = io.read(2).unpack1("n")
        expect(advance).to eq(100)

        # Remaining 4 glyphs only have LSBs (share last advance width)
        4.times do |_i|
          lsb = io.read(2).unpack1("n")
          expect(lsb).to be > 0
        end
      end
    end

    context "error handling" do
      it "raises EOFError on truncated data" do
        data = [0].pack("C") # Only flags

        expect do
          described_class.reconstruct(data, 3, 3, nil)
        end.to raise_error(EOFError, /Unexpected end of stream/)
      end

      it "handles empty transformation data" do
        data = +""

        expect do
          described_class.reconstruct(data, 1, 1, nil)
        end.to raise_error(EOFError)
      end
    end

    context "real-world scenarios" do
      it "handles typical web font metrics" do
        # Simulate typical web font with 100 glyphs, 50 unique advance widths
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_ADVANCE_WIDTHS |
          described_class::HMTX_FLAG_EXPLICIT_LSB_VALUES
        data << [flags].pack("C")

        # 50 advance widths
        50.times { |i| data << [200 + i].pack("C") }

        # 100 LSB values
        100.times { |i| data << [10 + i].pack("n") }

        result = described_class.reconstruct(data, 100, 50, nil)

        expect(result.bytesize).to eq((100 * 2) + (50 * 2)) # 50 full metrics + 50 LSBs
      end

      it "handles proportional font with variable widths" do
        # Proportional encoding with varying deltas
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_LSB_VALUES
        data << [flags].pack("C")

        # First width + deltas
        data << [100].pack("C") # First advance
        data << [20, -10, 5, -15].pack("n4") # Deltas

        # 5 LSB values
        data << [15, 20, 25, 30, 35].pack("n5")

        result = described_class.reconstruct(data, 5, 5, nil)

        io = StringIO.new(result)

        # Verify progressive deltas
        advances = []
        5.times do
          advances << io.read(2).unpack1("n")
          io.read(2) # Skip LSB
        end

        expect(advances[0]).to eq(100)
        expect(advances[1]).to eq(120)   # 100 + 20
        expect(advances[2]).to eq(110)   # 120 - 10
        expect(advances[3]).to eq(115)   # 110 + 5
        expect(advances[4]).to eq(100)   # 115 - 15
      end

      it "handles monospaced font optimization" do
        # Monospaced font: one advance width, all glyphs share it
        data = +""
        flags = described_class::HMTX_FLAG_EXPLICIT_LSB_VALUES
        data << [flags].pack("C")

        # Single advance width
        data << [120].pack("C")

        # LSBs for 10 glyphs
        10.times { |i| data << [10 + (i * 5)].pack("n") }

        result = described_class.reconstruct(data, 10, 1, nil)

        io = StringIO.new(result)

        # First glyph has full metric
        first_advance = io.read(2).unpack1("n")
        expect(first_advance).to eq(120)
        io.read(2) # Skip first LSB

        # Remaining 9 glyphs only have LSBs
        9.times do
          lsb = io.read(2).unpack1("n")
          expect(lsb).to be > 0
        end
      end
    end
  end
end
