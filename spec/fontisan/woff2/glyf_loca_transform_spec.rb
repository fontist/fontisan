# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::GlyfLocaTransform do
  let(:input_ttf) { fixture_path("fonttools/TestTTF.ttf") }

  let(:font) { Fontisan::FontLoader.load(input_ttf) }

  let(:transformer) do
    described_class.new(
      glyf_data: font.table_data["glyf"],
      loca_data: font.table_data["loca"],
      num_glyphs: font.table("maxp").num_glyphs,
      source_index_format: font.table("head").index_to_loc_format,
      target_format: Fontisan::Woff2::LocaFormat::SHORT,
    )
  end

  describe "#transform" do
    subject(:result) { transformer.transform }

    it "returns a binary string" do
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "writes the spec-mandated 36-byte header with target loca format" do
      # version (uint16) + optionFlags (uint16) + numGlyphs (uint16) +
      # indexFormat (uint16) + 7 × uint32 stream sizes
      version, option_flags, num_glyphs, index_format = result[0, 8].unpack("S>S>S>S>")
      expect(version).to eq(0)
      expect(num_glyphs).to eq(6)
      expect(index_format).to eq(Fontisan::Woff2::LocaFormat::SHORT.code)
      expect(option_flags).to eq(0) # TestTTF has no OVERLAP_SIMPLE glyphs
    end

    it "emits long loca indexFormat when target_format is LONG" do
      long_loca_path = fixture_path("fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf")
      long_loca_font = Fontisan::FontLoader.load(long_loca_path)
      skip "long-loca fixture missing" unless long_loca_font.table("head").index_to_loc_format == 1

      transformed = described_class.new(
        glyf_data: long_loca_font.table_data["glyf"],
        loca_data: long_loca_font.table_data["loca"],
        num_glyphs: long_loca_font.table("maxp").num_glyphs,
        source_index_format: 1, # source has long loca
        target_format: Fontisan::Woff2::LocaFormat::LONG,
      ).transform

      _, _, _, index_format = transformed[0, 8].unpack("S>S>S>S>")
      expect(index_format).to eq(1),
                              "glyf transform header should reflect target_format (LONG)"
    end

    it "writes 7 stream size prefixes after the header" do
      sizes = result[8, 28].unpack("L>L>L>L>L>L>L>")
      expect(sizes.sum + 36).to eq(result.bytesize),
                                "stream sizes + header must equal total transformed size"
    end

    it "encodes the nContour stream as int16[numGlyphs]" do
      # nContourStreamSize is at offset 8 (uint32); stream follows at offset 36.
      n_contour_size = result[8, 4].unpack1("L>")
      n_contour_stream = result[36, n_contour_size]
      contours = n_contour_stream.unpack("s>*")
      expect(contours.length).to eq(6) # numGlyphs
      # TestTTF glyphs: .notdef=2, .null/CR/space=0, period=1, ellipsis=-1
      expect(contours).to eq([2, 0, 0, 0, 1, -1])
    end

    it "produces output that matches fontTools byte-for-byte", :python do
      skip "fontTools not available" unless python_fonttools?

      # Write the comparison script to a temp file to avoid shell-quoting issues
      # with the long Python heredoc.
      Dir.mktmpdir do |dir|
        script_path = File.join(dir, "extract_fonttools_glyf.py")
        File.write(script_path, <<~PY)
          import sys, io, struct, brotli
          from fontTools.ttLib import TTFont
          font = TTFont(sys.argv[1])
          out = io.BytesIO()
          font.flavor = 'woff2'
          font.save(out)
          data = out.getvalue()
          num_tables = struct.unpack('>H', data[12:14])[0]
          compressed_size = struct.unpack('>I', data[20:24])[0]
          KNOWN = ['cmap','head','hhea','hmtx','maxp','name','OS/2','post','cvt ','fpgm','glyf','loca','prep','CFF ','VORG','EBDT','EBLC','gasp']
          pos = 48
          tags = []
          for i in range(num_tables):
              flags = data[pos]; pos += 1
              ti = flags & 0x3F; tv = (flags >> 6) & 3
              tag = bytes(data[pos:pos+4]).decode('ascii') if ti == 0x3F else KNOWN[ti]
              if ti == 0x3F: pos += 4
              orig = 0
              while True:
                  b = data[pos]; pos += 1
                  if b & 0x80: orig = (orig << 7) | (b & 0x7F)
                  else: orig = (orig << 7) | b; break
              has_tlen = (tag in ('glyf','loca') and tv == 0) or (tag == 'hmtx' and tv == 1)
              tlen = None
              if has_tlen:
                  tlen = 0
                  while True:
                      b = data[pos]; pos += 1
                      if b & 0x80: tlen = (tlen << 7) | (b & 0x7F)
                      else: tlen = (tlen << 7) | b; break
              tags.append((tag, tv, orig, tlen))
          decompressed = brotli.decompress(data[pos:pos+compressed_size])
          offset = 0
          for tag, tv, orig, tlen in tags:
              l = tlen if tlen is not None else orig
              if tag == 'glyf':
                  sys.stdout.buffer.write(decompressed[offset:offset+l])
                  break
              offset += l
        PY
        theirs = `python3 #{script_path} #{input_ttf}`
        expect(result.bytes).to eq(theirs.bytes),
                                "transformed glyf must match fontTools byte-for-byte"
      end
    end
  end

  describe "with empty glyf table" do
    let(:empty_glyf) { String.new(encoding: Encoding::BINARY) }
    let(:empty_loca) { [0, 0].pack("n*") } # 2 glyphs, both offset 0

    it "produces a valid empty transform" do
      t = described_class.new(
        glyf_data: empty_glyf,
        loca_data: empty_loca,
        num_glyphs: 1,
        source_index_format: 0,
        target_format: Fontisan::Woff2::LocaFormat::SHORT,
      )
      result = t.transform
      expect(result.bytesize).to be >= 36 # at least the header
    end
  end
end
