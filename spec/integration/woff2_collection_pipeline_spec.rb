# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "WOFF2 collection conversion pipeline", type: :integration do
  let(:ttc_path) { fixture_path("fonts/DinaRemasterII/DinaRemasterII.ttc") }

  it "round-trips TTC → WOFF2 collection → TTC with all fonts preserved" do
    Dir.mktmpdir do |dir|
      woff2_path = File.join(dir, "intermediate.woff2")
      ttc_out_path = File.join(dir, "round.ttc")

      # Step 1: TTC → WOFF2 collection via CollectionConverter
      converter = Fontisan::Converters::CollectionConverter.new
      converter.convert(ttc_path, target_type: :woff2_collection,
                                  options: { output: woff2_path })

      expect(File.exist?(woff2_path)).to be(true)
      expect(File.binread(woff2_path, 4)).to eq("wOF2")
      # flavor field at bytes 4-7 = 'ttcf' = 0x74746366
      expect(File.binread(woff2_path, 4, 4).unpack1("N")).to eq(0x74746366)

      # Step 2: WOFF2 collection → TTC via CollectionConverter
      converter.convert(woff2_path, target_type: :ttc,
                                    options: { output: ttc_out_path })

      expect(File.exist?(ttc_out_path)).to be(true)
      # TTC tag at bytes 0-3 = 'ttcf'
      expect(File.binread(ttc_out_path, 4)).to eq("ttcf")

      # Round-trip preserved all fonts
      decoded = Fontisan::FontLoader.load_collection(ttc_out_path)
      expect(decoded.num_fonts).to eq(2)
    end
  end

  it "detects WOFF2 collection files as collections" do
    Dir.mktmpdir do |dir|
      woff2_path = File.join(dir, "out.woff2")
      fonts = File.open(ttc_path, "rb") do |io|
        Fontisan::FontLoader.load_collection(ttc_path).extract_fonts(io)
      end
      bytes = Fontisan::Woff2::CollectionEncoder.new(brotli_quality: 11).encode_fonts(fonts)
      File.binwrite(woff2_path, bytes)

      expect(Fontisan::FontLoader.collection?(woff2_path)).to be(true)
      expect(Fontisan::FontLoader.detect_format(woff2_path)).to eq(:woff2_collection)
      expect(Fontisan::FontLoader.load_collection(woff2_path))
        .to be_a(Fontisan::Woff2Collection)
    end
  end
end
