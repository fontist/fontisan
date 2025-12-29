# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::GlyfTransformer do
  describe ".read_255_uint16" do
    it "reads single-byte values (< 253)" do
      io = StringIO.new([100].pack("C"))
      expect(described_class.send(:read_255_uint16, io)).to eq(100)
    end

    it "reads code 253 format (253 + uint16)" do
      # 253 followed by uint16 value
      io = StringIO.new([253, 100].pack("Cn"))
      expect(described_class.send(:read_255_uint16, io)).to eq(353) # 253 + 100
    end

    it "reads code 254 format (506 + uint16)" do
      # 254 followed by uint16 value
      io = StringIO.new([254, 100].pack("Cn"))
      expect(described_class.send(:read_255_uint16, io)).to eq(606) # 253*2 + 100
    end

    it "reads code 255 format (759 + uint16)" do
      # 255 followed by uint16 value
      io = StringIO.new([255, 100].pack("Cn"))
      expect(described_class.send(:read_255_uint16, io)).to eq(859) # 253*3 + 100
    end

    it "handles maximum single-byte value (252)" do
      io = StringIO.new([252].pack("C"))
      expect(described_class.send(:read_255_uint16, io)).to eq(252)
    end
  end

  describe ".parse_n_contour_stream" do
    it "parses contour counts for simple glyphs" do
      # Three glyphs: 1 contour, 2 contours, 3 contours
      data = [1, 2, 3].pack("n3")
      io = StringIO.new(data)
      result = described_class.send(:parse_n_contour_stream, io, 3)
      expect(result).to eq([1, 2, 3])
    end

    it "parses contour counts with composite glyphs (-1)" do
      # Mixed: simple, composite, simple
      data = [2, -1, 1].pack("n3")
      io = StringIO.new(data)
      result = described_class.send(:parse_n_contour_stream, io, 3)
      expect(result).to eq([2, -1, 1])
    end

    it "handles empty glyphs (0 contours)" do
      data = [0, 1, 0].pack("n3")
      io = StringIO.new(data)
      result = described_class.send(:parse_n_contour_stream, io, 3)
      expect(result).to eq([0, 1, 0])
    end
  end

  describe ".read_flags" do
    it "reads simple flags without repeat" do
      # Three flags with no repeat bit set
      data = [0x01, 0x02, 0x04].pack("C3")
      io = StringIO.new(data)
      result = described_class.send(:read_flags, io, 3)
      expect(result).to eq([0x01, 0x02, 0x04])
    end

    it "handles flag repeat" do
      # Flag with repeat bit (0x08) followed by repeat count
      flag_with_repeat = 0x01 | 0x08 # ON_CURVE_POINT | REPEAT_FLAG
      data = [flag_with_repeat, 3].pack("C2") # Repeat 3 times
      io = StringIO.new(data)
      result = described_class.send(:read_flags, io, 4)
      # Should return: original flag, then 3 repeats (total 4 flags)
      expect(result).to eq([flag_with_repeat, flag_with_repeat,
                            flag_with_repeat, flag_with_repeat])
    end

    it "handles multiple repeats in sequence" do
      # Two flags with repeats
      flag1 = 0x01 | 0x08 # Repeat flag
      flag2 = 0x02
      data = [flag1, 2, flag2].pack("C3") # First repeats 2 times, then regular flag
      io = StringIO.new(data)
      result = described_class.send(:read_flags, io, 4)
      expect(result).to eq([flag1, flag1, flag1, flag2])
    end
  end

  describe ".read_coordinates" do
    let(:short_flag) { described_class::X_SHORT_VECTOR }
    let(:same_or_positive_flag) do
      described_class::X_IS_SAME_OR_POSITIVE_X_SHORT_VECTOR
    end

    it "reads short positive deltas" do
      flags = [short_flag | same_or_positive_flag,
               short_flag | same_or_positive_flag]
      data = [10, 20].pack("C2") # Two positive deltas
      io = StringIO.new(data)
      result = described_class.send(:read_coordinates, io, flags, short_flag,
                                    same_or_positive_flag)
      expect(result).to eq([10, 30]) # Cumulative: 10, 10+20
    end

    it "reads short negative deltas" do
      flags = [short_flag, short_flag]  # Short but not positive
      data = [10, 20].pack("C2")
      io = StringIO.new(data)
      result = described_class.send(:read_coordinates, io, flags, short_flag,
                                    same_or_positive_flag)
      expect(result).to eq([-10, -30])  # Cumulative: -10, -10-20
    end

    it "handles same-as-previous (delta = 0)" do
      flags = [short_flag | same_or_positive_flag, same_or_positive_flag,
               short_flag | same_or_positive_flag]
      data = [10, 5].pack("C2") # Only two values needed
      io = StringIO.new(data)
      result = described_class.send(:read_coordinates, io, flags, short_flag,
                                    same_or_positive_flag)
      expect(result).to eq([10, 10, 15]) # 10, same (10), 10+5
    end

    it "reads long (16-bit) deltas" do
      flags = [0, 0] # Neither short nor same flags set
      data = [100, -50].pack("n2") # Two 16-bit signed values
      io = StringIO.new(data)
      result = described_class.send(:read_coordinates, io, flags, short_flag,
                                    same_or_positive_flag)
      # read_int16 converts: 100 stays 100, -50 as two's complement
      expect(result.first).to eq(100)
      expect(result.last).to eq(50) # 100 + (-50)
    end
  end

  describe ".build_simple_glyph_data" do
    it "builds minimal simple glyph data" do
      num_contours = 1
      x_min = 0
      y_min = 0
      x_max = 100
      y_max = 100
      end_pts = [3] # 4 points (0-3)
      instructions = +""
      flags = [0x01, 0x01, 0x01, 0x01] # ON_CURVE_POINT
      x_coords = [0, 100, 100, 0]
      y_coords = [0, 0, 100, 100]

      result = described_class.send(
        :build_simple_glyph_data,
        num_contours, x_min, y_min, x_max, y_max,
        end_pts, instructions, flags, x_coords, y_coords
      )

      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0

      # Verify structure
      io = StringIO.new(result)
      num_contours_read = io.read(2).unpack1("n")
      expect(num_contours_read).to eq(1)

      bbox = io.read(8).unpack("n4")
      expect(bbox).to eq([0, 0, 100, 100])
    end

    it "includes instructions when present" do
      num_contours = 1
      x_min = 0
      y_min = 0
      x_max = 100
      y_max = 100
      end_pts = [2] # 3 points
      instructions = "\x01\x02\x03" # Some instruction bytes
      flags = [0x01, 0x01, 0x01]
      x_coords = [0, 50, 100]
      y_coords = [0, 50, 100]

      result = described_class.send(
        :build_simple_glyph_data,
        num_contours, x_min, y_min, x_max, y_max,
        end_pts, instructions, flags, x_coords, y_coords
      )

      # Check that instruction length is encoded
      io = StringIO.new(result)
      io.read(10)  # Skip header and bbox
      io.read(2)   # Skip end points
      instruction_length = io.read(2).unpack1("n")
      expect(instruction_length).to eq(3)
    end
  end

  describe ".build_tables" do
    it "builds glyf and loca tables for simple glyphs" do
      glyphs = [
        "GLYPH1",  # 6 bytes
        "GLYPH22", # 7 bytes
        +"", # Empty glyph
      ]

      result = described_class.send(:build_tables, glyphs, 1) # Long format

      expect(result).to have_key(:glyf)
      expect(result).to have_key(:loca)

      # Verify glyf has all glyphs with padding
      glyf = result[:glyf]
      expect(glyf).to include("GLYPH1")
      expect(glyf).to include("GLYPH22")

      # Verify loca has correct number of offsets (num_glyphs + 1)
      loca = result[:loca]
      offsets = loca.unpack("N*") # Long format = 4 bytes each
      expect(offsets.size).to eq(4) # 3 glyphs + 1 final offset
      expect(offsets.first).to eq(0) # First offset always 0
    end

    it "uses short format for loca when index_format is 0" do
      glyphs = ["ABCD"] # 4 bytes

      result = described_class.send(:build_tables, glyphs, 0) # Short format

      loca = result[:loca]
      offsets = loca.unpack("n*") # Short format = 2 bytes each
      expect(offsets.size).to eq(2)  # 1 glyph + 1 final offset
      expect(offsets.first).to eq(0)
      expect(offsets.last).to eq(2)  # 4 bytes / 2 (short format divides by 2)
    end

    it "pads glyphs to 4-byte boundaries" do
      glyphs = ["A", "BB", "CCC"] # 1, 2, 3 bytes

      result = described_class.send(:build_tables, glyphs, 1)

      result[:glyf]
      loca = result[:loca]
      offsets = loca.unpack("N*")

      # Each glyph should be padded to 4-byte boundary
      expect(offsets[1] - offsets[0]).to eq(4)  # "A" + 3 padding
      expect(offsets[2] - offsets[1]).to eq(4)  # "BB" + 2 padding
      expect(offsets[3] - offsets[2]).to eq(4)  # "CCC" + 1 padding
    end
  end

  describe ".reconstruct_simple_glyph" do
    it "reconstructs a simple square glyph" do
      # Build minimal streams for a square - need complete data for all flags
      n_points_io = StringIO.new([3].pack("C")) # 4 points (end point = 3)

      # Flags: all on-curve with explicit coordinates
      flags = [0x01, 0x01, 0x01, 0x01] # Just ON_CURVE, will use long format coords
      flag_io = StringIO.new(flags.pack("C4"))

      # Coordinates as long (int16) format: 0, 100, 0, -100 for X; 0, 0, 100, 0 for Y
      glyph_data = +""
      glyph_data << [0, 100, 0, 65436].pack("n4")  # X coords (65436 = -100 as uint16)
      glyph_data << [0, 0, 100, 0].pack("n4")      # Y coords
      glyph_io = StringIO.new(glyph_data)

      bbox_io = StringIO.new([0, 0, 100, 100].pack("n4"))
      instruction_io = StringIO.new([0].pack("C")) # No instructions

      result = described_class.send(
        :reconstruct_simple_glyph,
        1, # num_contours
        n_points_io, flag_io, glyph_io, bbox_io, instruction_io
      )

      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0
    end
  end

  describe ".reconstruct" do
    context "with minimal transformed data" do
      it "reconstructs empty glyph table" do
        # Build minimal transformed data for 1 empty glyph
        data = +""
        data << [0].pack("N")  # version
        data << [1].pack("n")  # num_glyphs
        data << [0].pack("n")  # index_format (short)

        # Empty streams
        data << [2].pack("N")  # nContour stream size
        data << [0].pack("n")  # nContours = 0 (empty glyph)

        data << [0].pack("N")  # nPoints stream size
        data << [0].pack("N")  # flag stream size
        data << [0].pack("N")  # glyph stream size
        data << [0].pack("N")  # composite stream size
        data << [0].pack("N")  # bbox stream size
        data << [0].pack("N")  # instruction stream size

        result = described_class.reconstruct(data, 1)

        expect(result).to have_key(:glyf)
        expect(result).to have_key(:loca)
        expect(result[:loca].unpack("n*")).to eq([0, 0]) # Empty glyph
      end
    end

    context "error handling" do
      it "raises error on glyph count mismatch" do
        data = +""
        data << [0].pack("N")   # version
        data << [99].pack("n")  # Wrong num_glyphs
        data << [0].pack("n")   # index_format

        expect do
          described_class.reconstruct(data, 1) # Expecting 1 glyph
        end.to raise_error(Fontisan::InvalidFontError, /Glyph count mismatch/)
      end

      it "raises error on invalid nContours value" do
        data = +""
        data << [0].pack("N")  # version
        data << [1].pack("n")  # num_glyphs
        data << [0].pack("n")  # index_format

        # nContour stream with invalid value
        data << [2].pack("N") # nContour stream size
        data << [-99].pack("n") # Invalid nContours (not 0, >0, or -1)

        # Empty other streams
        data << [0].pack("N") * 6

        expect do
          described_class.reconstruct(data, 1)
        end.to raise_error(Fontisan::InvalidFontError,
                           /Invalid nContours value/)
      end

      it "raises InvalidFontError on truncated data" do
        data = [0].pack("N") # Only version field

        expect do
          described_class.reconstruct(data, 1)
        end.to raise_error(Fontisan::InvalidFontError, /too small/)
      end
    end
  end
end
