# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Woff2::CollectionEncoder do
  let(:ttc_path) { fixture_path("fonts/DinaRemasterII/DinaRemasterII.ttc") }
  let(:fonts) do
    File.open(ttc_path, "rb") do |io|
      Fontisan::FontLoader.load_collection(ttc_path).extract_fonts(io)
    end
  end

  let(:encoder) { described_class.new(brotli_quality: 11) }
  let(:result) { encoder.encode_fonts(fonts) }

  describe "#encode_fonts" do
    it "returns a binary string starting with 'wOF2' signature" do
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
      expect(result[0, 4]).to eq("wOF2")
    end

    it "sets flavor to 'ttcf' (0x74746366) for collection" do
      expect(result[4, 4].unpack1("N")).to eq(0x74746366)
    end

    it "header.length equals actual file size" do
      expect(result[8, 4].unpack1("N")).to eq(result.bytesize)
    end

    it "header.reserved is 0" do
      expect(result[14, 2].unpack1("n")).to eq(0)
    end

    it "emits a CollectionHeader after the table directory" do
      # Walk the table directory to find where collection header starts.
      num_tables = result[12, 2].unpack1("n")
      pos = 48
      Fontisan::Woff2::Directory::KNOWN_TAGS
      num_tables.times do
        flags = result.getbyte(pos)
        pos += 1
        ti = flags & 0x3F
        pos += 4 if ti == 0x3F
        loop do
          b = result.getbyte(pos)
          pos += 1
          break if (b & 0x80).zero?
        end
        tv = (flags >> 6) & 0x03
        is_glyf_loca = [10, 11].include?(ti)
        if is_glyf_loca && tv.zero?
          loop do
            b = result.getbyte(pos)
            pos += 1
            break if (b & 0x80).zero?
          end
        end
      end

      # CollectionHeader starts here
      version = result[pos, 4].unpack1("N")
      expect(version).to eq(0x00010000),
                         "CollectionHeader version should be 1.0"
      num_fonts = result.getbyte(pos + 4)
      expect(num_fonts).to eq(2), "numFonts should match the input TTC"
    end

    it "places loca immediately after glyf in the table directory" do
      num_tables = result[12, 2].unpack1("n")
      pos = 48
      known = Fontisan::Woff2::Directory::KNOWN_TAGS
      tags = []
      num_tables.times do
        flags = result.getbyte(pos)
        pos += 1
        ti = flags & 0x3F
        tag = ti == 0x3F ? result[pos, 4] : known[ti]
        pos += 4 if ti == 0x3F
        loop do
          b = result.getbyte(pos)
          pos += 1
          break if (b & 0x80).zero?
        end
        tv = (flags >> 6) & 0x03
        is_glyf_loca = [10, 11].include?(ti)
        if is_glyf_loca && tv.zero?
          loop do
            b = result.getbyte(pos)
            pos += 1
            break if (b & 0x80).zero?
          end
        end
        tags << tag
      end

      glyf_idx = tags.index("glyf")
      expect(glyf_idx).not_to be_nil, "glyf must be in table directory"
      expect(tags[glyf_idx + 1]).to eq("loca"),
                                    "loca MUST immediately follow glyf per spec section 5.5"
    end

    it "produces output decodable by woff2_decompress (W3C reference)", :slow do
      skip "woff2_decompress not installed" unless system("which woff2_decompress > /dev/null 2>&1")

      Dir.mktmpdir do |dir|
        woff2_path = File.join(dir, "out.woff2")
        ttc_path = File.join(dir, "out.ttf")
        File.binwrite(woff2_path, result)
        output = `cd #{dir} && woff2_decompress out.woff2 2>&1`
        expect(File.exist?(ttc_path)).to be(true),
                                         "woff2_decompress should produce out.ttf; got: #{output}"
        decoded = Fontisan::FontLoader.load_collection(ttc_path)
        expect(decoded.num_fonts).to eq(2)
      end
    end
  end
end
