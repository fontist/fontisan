# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Fontisan::Scan do
  let(:dir) { File.expand_path("../fixtures/fonttools", __dir__) }
  let(:ttf) { File.join(dir, "TestTTF.ttf") }
  let(:otf) { File.join(dir, "TestOTF.otf") }
  let(:ttc) { File.join(dir, "TestTTC.ttc") }
  let(:woff) { File.join(dir, "TestWOFF.woff") }
  let(:woff2) { File.join(dir, "TestWOFF2.woff2") }
  let(:vf) do
    File.expand_path("../fixtures/fonts/MonaSansVF/MonaSansVF[wght,opsz].ttf",
                     __dir__)
  end
  let(:work) { Dir.mktmpdir("scan-spec") }
  let(:all_fonts) { [ttf, otf, ttc, woff, woff2, vf] }

  after { FileUtils.rm_rf(work) }

  def write(name, bytes)
    File.join(work, name).tap { |path| File.binwrite(path, bytes) }
  end

  describe "a static font" do
    subject(:row) { Fontisan.scan([ttf]).first }

    it "carries path, hash, format and shape" do
      expect(row).to include("path" => ttf, "collection_index" => nil,
                             "format" => "ttf", "is_collection" => false,
                             "num_faces" => 1, "has_fvar" => false,
                             "sha256" => Digest::SHA256.file(ttf).hexdigest)
    end

    it "carries fontist's six names" do
      expect(row["names"]).to eq(
        "family_name" => "Test TTF", "full_name" => "Test TTF",
        "subfamily_name" => "Regular", "postscript_name" => "TestTTF-Regular",
        "preferred_family" => nil, "preferred_subfamily" => nil
      )
    end

    it "carries the raw indexability result" do
      expect(row["validation"]).to include("profile" => "indexability",
                                           "valid" => true, "issues" => [],
                                           "error_summary" => "")
    end

    it "has no errors and no instances" do
      expect(row["errors"].values).to all(satisfy { |e| e.nil? || e["class"] })
      expect(row["errors"]["font_file"]).to be_nil
      expect(row["variable_instances"]).to eq([])
    end

    it "says a single font is not a collection the way CollectionFile does" do
      expect(row["errors"]["collection_file"]).to eq(
        "class" => "Fontist::Errors::FontFileError",
        "message" => "File is not a recognized font collection (TTC/OTC/dfont)",
        "cause" => nil,
      )
    end
  end

  describe "a collection" do
    subject(:rows) { Fontisan.scan([ttc]) }

    it "gives one row per face" do
      expect(rows.map { |r| r.values_at("collection_index", "num_faces") })
        .to eq([[0, 2], [1, 2]])
      expect(rows.map { |r| r["is_collection"] }).to all(be(true))
    end

    it "records names with and without fontist's any-platform fallback" do
      expect(rows[1]["names"]["family_name"]).to eq("Test TTF")
      expect(rows[1]["english_names"]).to eq(rows[1]["names"])
    end

    it "has no collection error for an indexable first face" do
      expect(rows.map { |r| r["errors"]["collection_file"] }).to all(be_nil)
    end
  end

  describe "a variable font" do
    subject(:row) { Fontisan.scan([vf]).first }

    it "reads fvar through the second, full-mode load" do
      expect(row["has_fvar"]).to be(true)
      expect(row["variable_instances"]).not_to be_empty
    end

    it "applies fontist's RIBBI rule to each instance" do
      base = row["names"]["preferred_family"]
      row["variable_instances"].each do |inst|
        if %w[regular bold italic bold\ italic].include?(inst["style"].downcase) &&
            inst["family"] == base
          expect(inst["full_name"]).to eq("#{base} #{inst['style']}")
        else
          expect(inst).to include("style" => "Regular",
                                  "full_name" => inst["family"])
          expect(inst["family"]).to start_with("#{base} ")
        end
      end
    end
  end

  describe "other containers" do
    it "scans WOFF and WOFF2 like the sfnt originals" do
      rows = Fontisan.scan([woff, woff2])
      expect(rows.map { |r| r["format"] }).to eq(%w[woff woff2])
      expect(rows.map { |r| r["names"]["family_name"] }).to eq(["Test OTF", "Test TTF"])
    end
  end

  describe "bad input" do
    it "records fontist's FontFileError for garbage, without raising" do
      row = Fontisan.scan([write("g.ttf", "garbage garbage garbage")]).first
      expect(row["errors"]["font_file"]).to include(
        "class" => "Fontist::Errors::FontFileError",
        "cause" => a_hash_including("class" => "Fontisan::InvalidFontError"),
      )
      expect(row["errors"]["font_file"]["message"])
        .to start_with("Font file could not be parsed: #<Fontisan::InvalidFontError:")
      expect(row["names"]).to be_nil
    end

    it "records the RuntimeError of a tiny truncation" do
      row = Fontisan.scan([write("t.ttf", File.binread(ttf, 10))]).first
      expect(row["errors"]["font_file"]["cause"]["class"]).to eq("RuntimeError")
    end

    it "records a missing file as a row" do
      row = Fontisan.scan([File.join(work, "none.ttf")]).first
      expect(row["errors"]["font_file"]["cause"]["class"]).to eq("Errno::ENOENT")
      expect(row["sha256"]).to be_nil
    end

    it "wraps a failed collection load the way CollectionFile does" do
      path = write("c.ttc", File.binread(ttc, 20))
      row = Fontisan.scan([path]).first
      if row["is_collection"]
        expect(row["errors"]["collection_file"]["message"])
          .to start_with("Font collection could not be loaded:")
      end
      expect(row["errors"]["font_file"]).not_to be_nil
    end

    it "keeps the order of the input paths" do
      paths = [otf, ttf]
      expect(Fontisan.scan(paths).map { |r| r["path"] }).to eq(paths)
    end
  end

  describe "threads" do
    it "gives identical rows from concurrent scans" do
      sequential = Fontisan.scan(all_fonts)
      results = Array.new(8) do
        Thread.new { all_fonts.shuffle.flat_map { |f| Fontisan.scan([f]) } }
      end.map(&:value)

      results.each do |rows|
        expect(rows.sort_by { |r| [r["path"], r["collection_index"].to_i] })
          .to eq(sequential.sort_by { |r| [r["path"], r["collection_index"].to_i] })
      end
    end
  end

  it "is what Fontisan.scan returns" do
    expect(Fontisan.scan([ttf])).to eq(Fontisan::Reference.scan([ttf]))
  end
end
