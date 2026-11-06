# frozen_string_literal: true

require "tmpdir"
require_relative "support/corpus_paths"
require_relative "support/woff2_null_collection"

# fontisan#156 sweep: audit/scan of a WOFF2 collection whose glyf/loca use the
# null transform (version 3) raised InvalidFontError "numGlyphs mismatch": the
# decoder treated the raw glyf as a transformed stream.
RSpec.describe "WOFF2 collection with null-transformed glyf/loca" do
  let(:members) do
    path = CorpusPaths.path("woff2-collection-4members")
    Fontisan::Woff2::CollectionDecoder.new(File.binread(path)).decode
  end

  def write_collection(faces)
    path = File.join(Dir.mktmpdir, "null.woff2")
    File.binwrite(path, Woff2NullCollection.build(faces))
    path
  end

  def faces_without(*tags)
    members.map { |m| m[:tables].except(*tags) }
  end

  [[], ["cmap"], ["cvt "], ["hhea"], ["OS/2"]].each do |tags|
    context "with #{tags.empty? ? 'every table' : "#{tags.first} dropped"}" do
      let(:path) { write_collection(faces_without(*tags)) }

      it "decodes every member with its original glyf and loca" do
        decoded = Fontisan::Woff2::CollectionDecoder.new(File.binread(path)).decode

        expect(decoded.map { |m| m[:tables].slice("glyf", "loca") })
          .to eq(members.map { |m| m[:tables].slice("glyf", "loca") })
      end

      it "audits and scans without raising" do
        expect { Fontisan::Reference.audit(path) }.not_to raise_error
        expect { Fontisan::Reference.scan([path]) }.not_to raise_error
      end
    end
  end
end
