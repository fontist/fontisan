# frozen_string_literal: true

RSpec.describe Fontisan::Type1::PFBParser do
  describe ".pfb_file?" do
    it "returns true for valid PFB data with ASCII chunk" do
      # PFB with ASCII chunk marker (0x8001) in big-endian
      data = "\x80\u0001\u0004\u0000\u0000\u0000test"
      expect(described_class.pfb_file?(data)).to be true
    end

    it "returns true for valid PFB data with binary chunk" do
      # PFB with binary chunk marker (0x8002) in big-endian
      data = "\x80\u0002\u0004\u0000\u0000\u0000test"
      expect(described_class.pfb_file?(data)).to be true
    end

    it "returns false for nil data" do
      expect(described_class.pfb_file?(nil)).to be false
    end

    it "returns false for empty data" do
      expect(described_class.pfb_file?("")).to be false
    end

    it "returns false for data that is too short" do
      expect(described_class.pfb_file?("\x80")).to be false
    end

    it "returns false for non-PFB data" do
      expect(described_class.pfb_file?("some text")).to be false
    end
  end

  describe "#parse" do
    it "raises ArgumentError for nil data" do
      parser = described_class.new
      expect do
        parser.parse(nil)
      end.to raise_error(ArgumentError, /Data cannot be nil/)
    end

    it "raises ArgumentError for empty data" do
      parser = described_class.new
      expect do
        parser.parse("")
      end.to raise_error(ArgumentError, /Data cannot be empty/)
    end

    it "parses single ASCII chunk" do
      # Chunk: marker 0x8001, length 4, data "test"
      data = "\x80\x01\x04\x00\x00\x00test\x80\x03"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.ascii_parts).to eq(["test"])
      expect(result.binary_parts).to eq([])
      expect(result.ascii_text).to eq("test")
      expect(result.binary_data).to eq("")
    end

    it "parses single binary chunk" do
      # Chunk: marker 0x8002, length 4, data "bin\x00"
      data = "\x80\x02\x04\x00\x00\x00bin\x00\x80\x03"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.ascii_parts).to eq([])
      expect(result.binary_parts).to eq(["bin\x00"])
      expect(result.ascii_text).to eq("")
      expect(result.binary_data).to eq("bin\x00")
    end

    it "parses alternating ASCII and binary chunks" do
      # ASCII chunk: "hello", binary chunk: "world"
      data = "\x80\u0001\u0005\u0000\u0000\u0000hello\x80\u0002\u0005\u0000\u0000\u0000world\x80\u0003"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.ascii_parts).to eq(["hello"])
      expect(result.binary_parts).to eq(["world"])
    end

    it "parses multiple ASCII chunks" do
      # Three ASCII chunks
      data = "\x80\u0001\u0003\u0000\u0000\u0000foo\x80\u0001\u0003\u0000\u0000\u0000bar\x80\u0001\u0003\u0000\u0000\u0000baz\x80\u0003"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.ascii_parts).to eq(["foo", "bar", "baz"])
      expect(result.ascii_text).to eq("foobarbaz")
    end

    it "parses multiple binary chunks" do
      # Two binary chunks
      data = "\x80\u0002\u0003\u0000\u0000\u0000abc\x80\u0002\u0003\u0000\u0000\u0000def\x80\u0003"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.binary_parts).to eq(["abc", "def"])
      expect(result.binary_data).to eq("abcdef")
    end

    it "handles zero-length chunks" do
      # ASCII chunk with zero length
      data = "\x80\x01\x00\x00\x00\x00\x80\x03"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.ascii_parts).to eq([""])
    end

    it "handles large chunk lengths" do
      # Create a 10KB chunk
      large_data = "x" * 10_240
      length_bytes = [10_240].pack("V")

      data = "\x80\u0001#{length_bytes}#{large_data}\x80\u0003"
      parser = described_class.new
      result = parser.parse(data)

      expect(result.ascii_parts).to eq([large_data])
    end

    context "error handling" do
      it "raises error for incomplete chunk header" do
        data = "\x80\x01" # No length bytes
        parser = described_class.new

        expect { parser.parse(data) }
          .to raise_error(Fontisan::Error, /incomplete length/)
      end

      it "raises error for incomplete chunk data" do
        data = "\x80\x01\x0A\x00\x00\x00short" # Length 10 but only 5 bytes
        parser = described_class.new

        expect { parser.parse(data) }
          .to raise_error(Fontisan::Error, /length.*exceeds remaining data/)
      end

      it "raises error for unknown chunk marker" do
        data = "\x80\xFF\x04\x00\x00\x00test" # Invalid marker 0x80FF
        parser = described_class.new

        expect { parser.parse(data) }
          .to raise_error(Fontisan::Error, /unknown chunk marker/)
      end
    end
  end

  describe "#parsed?" do
    it "returns false before parsing" do
      parser = described_class.new
      expect(parser.parsed?).to be false
    end

    it "returns true after parsing" do
      parser = described_class.new
      parser.parse("\x80\x01\x04\x00\x00\x00test\x80\x03")
      expect(parser.parsed?).to be true
    end
  end
end
