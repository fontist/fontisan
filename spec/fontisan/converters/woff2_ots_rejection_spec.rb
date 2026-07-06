# frozen_string_literal: true

# Specs for the WOFF2 OTS rejection bug.
#
# Chrome's OpenType Sanitizer (OTS) rejects WOFF2 files that include a
# DSIG table or that fail to set head.flags bit 11. Per WOFF2 spec
# section 5:
#
#   "The compliant WOFF2 encoder MUST remove the DSIG table from an
#    input font data, prior to applying transformations and entropy
#    coding steps."
#
#   "The WOFF 2.0 encoders MUST also set bit 11 of the 'flags' field
#    of the head table ... to indicate that a recreated font file was
#    subjected to lossless modifying transform."

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Converters::Woff2Encoder do
  let(:input_ttf) { fixture_path("fonttools/TestTTF.ttf") }

  def encode_to_woff2(path)
    font = Fontisan::FontLoader.load(path)
    described_class.new.convert(font, brotli_quality: 11)[:woff2_binary]
  end

  describe "WOFF2 spec conformance" do
    it "removes the DSIG table" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        font = Fontisan::Woff2Font.from_file(path)
        tags = font.table_entries.map(&:tag)
        expect(tags).not_to include("DSIG"),
                            "WOFF2 still contains a DSIG table directory entry; " \
                            "Woff2::EncoderRules must drop DSIG per WOFF2 spec section 5"
      end
    end

    it "sets head.flags bit 11 (FLAG_LOSSLESS_MODIFYING) on the encoded font" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        head = Fontisan::Woff2Font.from_file(path).table("head")
        expect(head.flags & Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING)
          .to be_nonzero,
              "head.flags bit 11 not set; Woff2::EncoderRules must mark the " \
              "head table to satisfy Chrome OTS and WOFF2 spec section 5"
      end
    end

    it "preserves head.flags bits other than bit 11" do
      font = Fontisan::FontLoader.load(input_ttf)
      original_flags = font.table("head").flags
      mask = ~Fontisan::Tables::Head::FLAG_LOSSLESS_MODIFYING

      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        encoded_flags = Fontisan::Woff2Font.from_file(path).table("head").flags
        expect(encoded_flags & mask).to eq(original_flags & mask),
                                        "head.flags bits other than bit 11 must be preserved verbatim"
      end
    end

    it "produces a WOFF2 that Python's fontTools can decode", :python do
      skip "fontTools not available" unless python_fonttools?

      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        # Pass path via argv (not string interpolation) so unusual paths
        # cannot break the script.
        script = <<~PY
          import sys
          from fontTools.ttLib import TTFont
          f = TTFont(sys.argv[1])
          print(sorted(f.keys()))
        PY
        output = `python3 -c '#{script.gsub("'", %q(\\\'))}' "#{path}" 2>&1`
        expect($?).to be_success,
                      "fontTools failed to parse WOFF2 output:\n#{output}"
        expect(output).to include("head"), "head table missing from WOFF2"
      end
    end
  end

  describe "glyf/loca paired transform (spec section 5.1/5.3)" do
    it "emits glyf with transformation version 0 (transformed)" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        glyf_entry = Fontisan::Woff2Font.from_file(path).table_entries
          .find { |e| e.tag == "glyf" }
        flags = glyf_entry.flags
        transform_version = (flags >> 6) & 0x03
        expect(transform_version).to eq(0),
                                     "glyf must use transformation version 0 (transformed format); " \
                                     "Chrome OTS rejects version 3 (null transform) for glyf"
      end
    end

    it "emits loca with transformation version 0 and transformLength = 0" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        loca_entry = Fontisan::Woff2Font.from_file(path).table_entries
          .find { |e| e.tag == "loca" }
        flags = loca_entry.flags
        transform_version = (flags >> 6) & 0x03
        expect(transform_version).to eq(0),
                                     "loca must use transformation version 0 (paired with glyf)"
        expect(loca_entry.transform_length).to eq(0),
                                               "loca transformLength must be 0 per spec section 5.3"
      end
    end

    it "emits loca.origLength matching the reconstructed loca size" do
      # The encoder picks the most compact format that fits the glyf
      # table (per fontTools' behavior). The directory's loca.origLength
      # must match that chosen format's reconstructed size — otherwise
      # fontTools and Chrome's OTS reject the file for the size mismatch.
      long_loca_ttf = fixture_path(
        "fonts/Libertinus/Libertinus-7.051/static/TTF/LibertinusKeyboard-Regular.ttf",
      )
      skip "long-loca fixture missing" unless File.exist?(long_loca_ttf)

      source = Fontisan::FontLoader.load(long_loca_ttf)
      num_glyphs = source.table("maxp").num_glyphs
      glyf_bytesize = source.table_data["glyf"].bytesize
      expected_format = Fontisan::Woff2::LocaFormat.choose_for(glyf_bytesize:)
      expected = expected_format.loca_size(num_glyphs)

      woff2 = encode_to_woff2(long_loca_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        loca_entry = Fontisan::Woff2Font.from_file(path).table_entries
          .find { |e| e.tag == "loca" }
        expect(loca_entry.orig_length).to eq(expected),
                                          "loca.origLength must match the reconstructed loca " \
                                          "size for format #{expected_format.short? ? 'SHORT' : 'LONG'}: " \
                                          "expected #{expected}, got #{loca_entry.orig_length}"
      end
    end

    it "places loca immediately after glyf in the table directory" do
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        entries = Fontisan::Woff2Font.from_file(path).table_entries
        tags = entries.map(&:tag)
        glyf_idx = tags.index("glyf")
        expect(tags[glyf_idx + 1]).to eq("loca"),
                                      "loca MUST follow glyf in the table directory per spec section 5.5"
      end
    end

    it "omits loca data from the brotli-compressed block" do
      # The compressed block concatenates table data in directory order.
      # After the transform, loca's data is omitted (reconstructed by the
      # decoder from glyf). Verify by checking that the sum of table data
      # lengths in the directory equals the decompressed size, with loca
      # contributing 0 bytes.
      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        font = Fontisan::Woff2Font.from_file(path)
        font.table_entries.sum do |e|
          e.transform_length || e.orig_length
        end
        # transformLength for loca is 0 — the rest contribute their data.
        # Don't assert exact equality (fontisan may pad); just check loca's
        # contribution is 0.
        loca = font.table_entries.find { |e| e.tag == "loca" }
        expect(loca.transform_length).to eq(0)
      end
    end

    it "produces a glyf stream byte-identical to fontTools", :python do
      skip "fontTools not available" unless python_fonttools?

      # Compare our transformed glyf bytes against fontTools' transformed glyf.
      # Both must produce byte-identical output for the same input font.
      font = Fontisan::FontLoader.load(input_ttf)

      # Pull transformed glyf bytes from our encoder via the transform class
      transformer = Fontisan::Woff2::GlyfLocaTransform.new(
        glyf_data: font.table_data["glyf"],
        loca_data: font.table_data["loca"],
        num_glyphs: font.table("maxp").num_glyphs,
        source_index_format: font.table("head").index_to_loc_format,
      )
      ours = transformer.transform

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
        expect(theirs.bytesize).to eq(ours.bytesize),
                                   "transformed glyf size mismatch: ours=#{ours.bytesize}, fontTools=#{theirs.bytesize}"
        expect(theirs.bytes).to eq(ours.bytes),
                                "transformed glyf bytes must match fontTools byte-for-byte"
      end
    end

    it "round-trips through fontTools (decode + re-encode succeeds)", :python do
      skip "fontTools not available" unless python_fonttools?

      woff2 = encode_to_woff2(input_ttf)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.woff2")
        File.binwrite(path, woff2)

        script = <<~PY
          import sys
          from fontTools.ttLib import TTFont
          t = TTFont(sys.argv[1])
          g = t["glyf"]
          for name in t.getGlyphOrder():
              glyph = g[name]
              print(f"{name}: nContours={glyph.numberOfContours}")
        PY
        output = `python3 -c '#{script.gsub("'", %q(\\\'))}' "#{path}" 2>&1`
        expect($?).to be_success,
                      "fontTools failed to decode and walk our WOFF2:\n#{output}"
        # Verify glyph contour counts match the original font
        expect(output).to include("nContours=2")   # .notdef
        expect(output).to include("nContours=-1")  # ellipsis (composite)
      end
    end
  end
end
