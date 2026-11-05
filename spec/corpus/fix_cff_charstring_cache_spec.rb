# frozen_string_literal: true

require_relative "support/corpus_paths"

RSpec.describe Fontisan::Tables::Cff do
  let(:cff) do
    font = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-regular-otf"), mode: :full)
    font.table("CFF ")
  end

  # charstring_for_glyph re-parsed the whole CharStrings INDEX for every
  # glyph, so a 17,936-glyph CJK font took minutes to audit with --validate.
  it "parses the CharStrings INDEX once for many glyph lookups" do
    allow(Fontisan::Tables::Cff::CharstringsIndex).to receive(:new).and_call_original

    glyphs = Array.new(50) { |gid| cff.charstring_for_glyph(gid) }

    expect(Fontisan::Tables::Cff::CharstringsIndex).to have_received(:new).once
    expect(glyphs.compact.size).to eq(50)
  end

  it "returns the same charstring as a table that has not been cached" do
    fresh = Fontisan::FontLoader.load(CorpusPaths.path("source-sans-3-regular-otf"), mode: :full).table("CFF ")
    cff.charstring_for_glyph(7)

    expect(cff.charstring_for_glyph(7).to_commands).to eq(fresh.charstring_for_glyph(7).to_commands)
  end
end
