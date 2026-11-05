# frozen_string_literal: true

require "fontisan"
require "fileutils"
require "tmpdir"

# The two collection-error branches of Fontisan::Scan that no corpus font
# reaches (every corpus collection indexes cleanly).
RSpec.describe Fontisan::Scan do # rubocop:disable RSpec/SpecFilePathFormat
  let(:header) { "ttcf".b + [1, 0, 1, 16].pack("nnNN") }
  let(:dir) { Dir.mktmpdir("scan-branches") }

  after { FileUtils.rm_rf(dir) }

  def row_for(bytes)
    path = File.join(dir, "c.ttc")
    File.binwrite(path, bytes)
    described_class.call([path])
  end

  it "records a first face that fails indexability as the validation error" do
    rows = row_for(header + [0x00010000, 0, 0, 0, 0].pack("Nnnnn"))
    error = rows.first[:errors][:collection_file]

    expect(rows.size).to eq(1)
    expect(error[:class]).to eq("Fontist::Errors::FontIndexabilityValidationError")
    expect(error[:message]).to start_with("Font collection failed indexability validation (first font): ")
    expect(rows.first[:validation][:valid]).to be(false)
  end

  it "records a first face that cannot be loaded as a wrapped load failure" do
    rows = row_for(header + [0x00010000, 5, 0, 0, 0].pack("Nnnnn"))

    expect(rows.first[:errors][:collection_file])
      .to include(class: "Fontist::Errors::FontFileError",
                  message: "Font collection could not be loaded: End of file reached")
    expect(rows.first[:errors][:font_file][:message]).to include("EOFError")
  end

  it "gives a collection without faces a row of its own to carry the error" do
    rows = row_for("ttcf".b + [1, 0, 0].pack("nnN"))

    expect(rows.size).to eq(1)
    expect(rows.first).to include(collection_index: nil, num_faces: 0, is_collection: true)
    expect(rows.first[:errors][:collection_file][:message]).to start_with("Font collection could not be loaded: ")
  end

  # FontLoader.load_collection does not fail for any byte string that
  # FontLoader.collection? accepts (the classes parse lazily), so no input
  # reaches this branch; it is covered by forcing the failure.
  it "wraps a collection that fails to load, on one row" do
    path = File.join(dir, "c.ttc")
    File.binwrite(path, header + [0x00010000, 0, 0, 0, 0].pack("Nnnnn"))
    allow(Fontisan::FontLoader).to receive(:load_collection).and_raise(Fontisan::InvalidFontError, "boom")

    rows = described_class.call([path])

    expect(rows.size).to eq(1)
    expect(rows.first[:errors][:collection_file])
      .to include(message: "Font collection could not be loaded: boom")
    expect(rows.first[:errors][:font_file][:message]).to include("boom")
  end
end
