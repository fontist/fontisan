# frozen_string_literal: true

require "tmpdir"
require_relative "support/corpus_paths"

# Scan rows against fontist at 85e904c96fff60f60781ae0eb11a8c06e0c73816
# (fontist/fontisan#156, card 0f). fontist is a dev-only Gemfile dependency
# (group :fontist_parity); without it this file skips.
#
# Scan is meant to carry what fontist's FontFile and CollectionFile read, so
# each row is compared field by field with what those classes return or raise
# for the same file.
module FontistParity
  NAME_KEYS = %i[family_name full_name subfamily_name preferred_family preferred_subfamily postscript_name].freeze
  ENGLISH_KEYS = (NAME_KEYS - [:postscript_name]).freeze

  AVAILABLE = begin
    require "fontist"
    true
  rescue LoadError
    false
  end

  module_function

  def error_hash(error)
    cause = error.cause
    { "class" => error.class.name, "message" => error.message,
      "cause" => cause && { "class" => cause.class.name, "message" => cause.message } }
  end

  def stringify(hash)
    hash.to_h { |k, v| [k.to_s, v] }
  end

  # FontFile.extract_font_info_from_path: [info, nil] or [nil, error].
  def font_file(path)
    [Fontist::FontFile.extract_font_info_from_path(path), nil]
  rescue Fontist::Errors::FontFileError => e
    [nil, e]
  end

  # CollectionFile.from_path: [collection file, nil] or [nil, error].
  def collection_file(path)
    Fontist::CollectionFile.from_path(path) { |collection| return [collection, nil] }
  rescue Fontist::Errors::FontFileError => e
    [nil, e]
  end

  # What CollectionFile#[] returns or raises for one member.
  def member(collection, index)
    [collection[index], nil]
  rescue StandardError => e
    [nil, e]
  end
end

RSpec.describe "Fontisan::Reference.scan against fontist", if: FontistParity::AVAILABLE do
  let(:parity) { FontistParity }

  def scan(path)
    Fontisan::Reference.scan([path])
  end

  def expect_font_file_parity(row, info, error)
    if error
      expect(row["errors"]["font_file"]).to eq(parity.error_hash(error))
      expect(row["names"]).to be_nil
    else
      expect(row["errors"]["font_file"]).to be_nil
      expect(row["names"]).to eq(parity.stringify(info.slice(*FontistParity::NAME_KEYS)))
      expect(row["variable_instances"]).to eq((info[:variable_instances] || []).map { |i| parity.stringify(i) })
    end
  end

  def expect_member_parity(row, collection)
    member, error = parity.member(collection, row["collection_index"])
    if error
      expect(row["errors"]["collection_member"])
        .to eq("class" => error.class.name, "message" => error.message)
    else
      expect(row["errors"]["collection_member"]).to be_nil
      expect(row["english_names"].slice(*FontistParity::ENGLISH_KEYS.map(&:to_s))).to eq(
        "family_name" => member.family, "full_name" => member.full_name,
        "subfamily_name" => member.subfamily, "preferred_family" => member.preferred_family_name,
        "preferred_subfamily" => member.preferred_subfamily_name
      )
    end
  end

  def expect_collection_parity(rows, collection, error)
    if error
      expect(rows.map { |r| r["errors"]["collection_file"] }.uniq).to eq([parity.error_hash(error)])
    else
      expect(rows.size).to eq(collection.count)
      rows.each do |row|
        expect(row["errors"]["collection_file"]).to be_nil
        expect_member_parity(row, collection)
      end
    end
  end

  def expect_parity(path)
    rows = scan(path)
    info, ferr = parity.font_file(path)
    collection, cerr = parity.collection_file(path)
    expect_font_file_parity(rows.first, info, ferr)
    expect_collection_parity(rows, collection, cerr)
    [rows, cerr]
  end

  def present_ids
    CorpusPaths.manifest.fetch("fonts").map { |e| e["id"] }.select { |id| File.exist?(CorpusPaths.path(id)) }
  end

  describe "every corpus font on disk" do
    it "has the whole ci tier to compare" do
      expect(present_ids.size).to be >= 44
    end

    it "matches FontFile for the first (or only) face and CollectionFile for the file" do
      mismatches = present_ids.filter_map do |id|
        expect_parity(CorpusPaths.path(id))
        nil
      rescue RSpec::Expectations::ExpectationNotMetError => e
        "#{id}: #{e.message.lines.first(8).join}"
      end
      expect(mismatches).to eq([])
    end
  end

  describe "the comparison sees real values" do
    let(:ttf) { CorpusPaths.path("source-sans-3-regular-ttf") }
    let(:vf) { CorpusPaths.path("noto-sans-vf-wdth-wght") }
    let(:ttc) { CorpusPaths.path("fonttools-test-ttc") }

    it "reads fontist's names for a static font" do
      info, = parity.font_file(ttf)
      expect(info[:family_name]).to eq("Source Sans 3")
      expect(scan(ttf).first["names"]["family_name"]).to eq("Source Sans 3")
    end

    it "reads fontist's variable instances, which are not an empty list" do
      info, = parity.font_file(vf)
      expect(info[:variable_instances]).not_to be_empty
      expect(scan(vf).first["variable_instances"]).to eq(info[:variable_instances].map { |i| parity.stringify(i) })
    end

    it "lists one row per member of a collection that CollectionFile enumerates" do
      collection, error = parity.collection_file(ttc)
      expect(error).to be_nil
      expect(collection.count).to eq(2)
      expect(scan(ttc).map { |r| r["collection_index"] }).to eq([0, 1])
    end

    it "finds Windows non-ASCII and Mac-only names through the any-platform fallback" do
      %w[names-windows-nonascii-only names-mac-roman-only].each do |id|
        path = CorpusPaths.path(id)
        info, error = parity.font_file(path)
        expect(error).to be_nil
        expect(scan(path).first["names"]).to eq(parity.stringify(info.slice(*FontistParity::NAME_KEYS)))
      end
    end

    it "wraps the not-a-collection raise the way CollectionFile does" do
      _, error = parity.collection_file(ttf)
      expect(error.message).to eq("Font collection could not be loaded: File is not a recognized font collection (TTC/OTC/dfont)")
      expect(scan(ttf).first["errors"]["collection_file"]).to eq(parity.error_hash(error))
    end
  end

  describe "collections fontist rejects" do
    # Built here, 28 bytes each: a ttcf header plus one face.
    let(:header) { "ttcf".b + [1, 0, 1, 16].pack("nnNN") }
    let(:no_tables) { header + [0x00010000, 0, 0, 0, 0].pack("Nnnnn") }
    let(:cut_directory) { header + [0x00010000, 5, 0, 0, 0].pack("Nnnnn") }
    let(:zero_faces) { "ttcf".b + [1, 0, 0].pack("nnN") }

    def fixture(dir, name, bytes)
      File.join(dir, name).tap { |path| File.binwrite(path, bytes) }
    end

    it "raises FontIndexabilityValidationError for a first face that fails indexability" do
      Dir.mktmpdir do |dir|
        rows, error = expect_parity(fixture(dir, "no-tables.ttc", no_tables))
        expect(error).to be_a(Fontist::Errors::FontIndexabilityValidationError)
        expect(error.message).to start_with("Font collection failed indexability validation (first font): ")
        expect(rows.size).to eq(1)
      end
    end

    it "wraps a first face that cannot be loaded as 'Font collection could not be loaded'" do
      Dir.mktmpdir do |dir|
        rows, error = expect_parity(fixture(dir, "cut-directory.ttc", cut_directory))
        expect(error.message).to eq("Font collection could not be loaded: End of file reached")
        expect(rows.size).to eq(1)
      end
    end

    it "wraps a collection with no faces the same way, on a row of its own" do
      Dir.mktmpdir do |dir|
        rows, error = expect_parity(fixture(dir, "zero-faces.ttc", zero_faces))
        expect(error.message).to start_with("Font collection could not be loaded: ")
        expect(rows.size).to eq(1)
        expect(rows.first["num_faces"]).to eq(0)
      end
    end
  end
end
