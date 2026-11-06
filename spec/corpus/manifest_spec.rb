# frozen_string_literal: true

require "json"
require "digest"
require_relative "../../corpus/derive/sfnt"

# Structure and coverage of corpus/manifest.json (fontist/fontisan#157, card 0a).
# Needs no network: it reads the manifest and the committed corpus/derived
# files. Examples that sniff fetched fonts need `rake corpus:fetch` first (CI
# runs it before this spec) and say so when skipped.
# The manifest is read once at load time because examples are generated per
# entry, so the locals below are intentionally shared with the example blocks.
# rubocop:disable RSpec/LeakyLocalVariable
module CorpusSpecHelper
  module_function

  def path_of(root, entry)
    if entry["type"] == "derived"
      File.join(root, "corpus", "derived", entry["file"])
    else
      File.join(root, "corpus", "fonts", entry["id"], entry["file"])
    end
  end

  def tables(path)
    CorpusSfnt.parse(File.binread(path)).last.to_h
  end
end

RSpec.describe "corpus manifest" do # rubocop:disable RSpec/DescribeClass
  root = File.expand_path("../..", __dir__)
  manifest = JSON.parse(File.read(File.join(root, "corpus", "manifest.json")))
  fonts = manifest.fetch("fonts")
  by_id = fonts.to_h { |f| [f["id"], f] }
  whitelist = %w[OFL-1.1 Apache-2.0 MIT]

  # #157 corpus rows, each as a `covers` tag.
  issue_rows = {
    "static TTF small" => "static-ttf-small",
    "static TTF large" => "static-ttf-large",
    "static TTF hinted" => "static-ttf-hinted",
    "static OTF small" => "static-otf-small",
    "static OTF large" => "static-otf-large",
    "TTC with 2 members" => "ttc-2-members",
    "TTC with more members" => "ttc-more-members",
    "large TTC collection (nightly)" => "ttc-large-collection",
    "WOFF" => "woff",
    "WOFF2" => "woff2",
    "WOFF2 collection" => "woff2-collection",
    "VF with fvar/gvar/HVAR" => "vf-fvar-gvar-hvar",
    "VF named instances: weight" => "vf-named-weight",
    "VF named instances: width" => "vf-named-width",
    "VF named instances: italic" => "vf-named-italic",
    "CFF2" => "cff2",
    "empty tables" => "empty-tables",
    "version quirks" => "version-quirks",
    "non-ASCII Mac names" => "name-mac-nonascii",
    "non-ASCII Windows names" => "name-windows-nonascii",
    "routing proof: dfont" => "routing-dfont",
    "routing proof: Type 1" => "routing-type1",
  }.freeze
  malformed_kinds = %w[truncated-10 truncated-100 truncated-half garbage empty
                       bad-table-offset bad-checksum bad-num-tables
                       fuzz-cmap12-u32-span fuzz-cff2-huge-count fuzz-ttc-head-offset
                       woff-corrupt-deflate woff-zero-table-dir woff-truncated-half
                       woff2-corrupt-brotli woff2-zero-table-dir woff2-truncated-half].freeze

  it "has the expected schema and two tiers" do
    expect(manifest["schema"]).to eq(1)
    expect(manifest["tiers"]).to eq(%w[ci large])
    expect(manifest["licence_whitelist"]).to eq(whitelist)
    expect(fonts.map { |f| f["tier"] }.uniq.sort).to eq(%w[ci large])
  end

  it "has unique ids and unique file names per kind" do
    ids = fonts.map { |f| f["id"] }
    expect(ids).to eq(ids.uniq)
    expect(ids).to all(match(/\A[a-z0-9][a-z0-9-]*\z/))
  end

  describe "every entry" do
    fonts.each do |entry|
      context entry["id"] do
        it "has a whitelisted licence with a real licence file" do
          expect(whitelist).to include(entry["licence"])
          file = File.join(root, entry["licence_file"])
          expect(File.size(file)).to be_positive
          text = File.read(file)
          if entry["licence"] == "OFL-1.1"
            expect(text).to match(/SIL Open Font License/i)
          elsif entry["licence"] == "MIT"
            expect(text).to include("Permission is hereby granted")
          end
        end

        it "has a sha256 and a size" do
          expect(entry["sha256"]).to match(/\A\h{64}\z/)
          expect(entry["size"]).to be_a(Integer)
        end
      end
    end
  end

  describe "source entries" do
    sources = fonts.select { |f| f["type"] == "source" }

    it "pin every URL to a commit SHA or a release asset (nothing floating)" do
      sources.each do |e|
        url = e.dig("source", "url")
        pinned = url.match?(%r{\Ahttps://raw\.githubusercontent\.com/[^/]+/[^/]+/\h{40}/}) ||
          url.match?(%r{\Ahttps://github\.com/[^/]+/[^/]+/releases/download/[^/]+/[^/]+\z})
        expect(pinned).to be(true), "#{e['id']} has a floating URL: #{url}"
        expect(url).not_to match(%r{/(main|master|HEAD)/|refs/heads})
      end
    end

    it "record the pin and use archive_member only for release zips" do
      sources.each do |e|
        expect(e.dig("source", "pin")).not_to be_nil
        next unless e.dig("source", "archive_member")

        expect(e.dig("source", "url")).to end_with(".zip")
      end
    end

    it "keep the ci tier under 20 MB of downloads" do
      ci = sources.select { |e| e["tier"] == "ci" }.sum { |e| e["size"] }
      expect(ci).to be < 20 * 1024 * 1024
    end

    it "put the very large fonts in the large tier" do
      expect(sources.select { |e| e["size"] > 8 * 1024 * 1024 }.map { |e| e["tier"] }.uniq).to eq(["large"])
    end
  end

  describe "derived entries" do
    derived = fonts.select { |f| f["type"] == "derived" }

    derived.each do |entry|
      context entry["id"] do
        it "is committed with a matching sha256 and size" do
          path = CorpusSpecHelper.path_of(root, entry)
          expect(File).to exist(path)
          expect(File.size(path)).to eq(entry["size"])
          expect(Digest::SHA256.file(path).hexdigest).to eq(entry["sha256"])
        end

        it "names its derive script and inputs" do
          expect(File).to exist(File.join(root, entry["script"]))
          expect(entry["inputs"]).not_to be_empty
          expect(entry["inputs"]).to all(satisfy { |i| by_id.key?(i) })
        end
      end
    end

    it "only commits small files" do
      expect(derived.sum { |e| e["size"] }).to be < 256 * 1024
    end

    it "has no committed file outside the manifest" do
      on_disk = Dir.children(File.join(root, "corpus", "derived")).sort
      expect(on_disk).to eq(derived.map { |e| e["file"] }.sort)
    end
  end

  describe "#157 coverage" do
    issue_rows.each do |row, tag|
      it "covers #{row}" do
        expect(fonts.select { |f| f["covers"].include?(tag) }).not_to be_empty
      end
    end

    it "has at least one ci-tier entry for every row except the nightly one" do
      (issue_rows.values - ["ttc-large-collection"]).each do |tag|
        ci = fonts.select { |f| f["tier"] == "ci" && f["covers"].include?(tag) }
        expect(ci).not_to be_empty, "no ci entry for #{tag}"
      end
    end

    it "covers the large TTC collection in the large tier" do
      large = fonts.select { |f| f["tier"] == "large" && f["covers"].include?("ttc-large-collection") }
      expect(large).not_to be_empty
    end
  end

  describe "malformed set" do
    it "has one derived entry per malformed kind" do
      kinds = fonts.map { |f| f["malformed_kind"] }.compact
      expect(kinds.sort).to eq(malformed_kinds.sort)
      expect(fonts.select { |f| f["malformed_kind"] }.map { |f| f["type"] }.uniq).to eq(["derived"])
    end

    it "produces the shapes its names promise" do
      size = ->(kind) { File.size(CorpusSpecHelper.path_of(root, fonts.find { |f| f["malformed_kind"] == kind })) }
      bytes = ->(kind) { File.binread(CorpusSpecHelper.path_of(root, fonts.find { |f| f["malformed_kind"] == kind })) }
      expect(size.call("truncated-10")).to eq(10)
      expect(size.call("truncated-100")).to eq(100)
      expect(size.call("empty")).to eq(0)
      expect(size.call("truncated-half")).to eq(size.call("bad-checksum") / 2)
      expect(bytes.call("bad-num-tables").byteslice(4, 2).unpack1("n")).to eq(0xFFFF)
      offset = bytes.call("bad-table-offset").byteslice(12 + 8, 4).unpack1("N")
      expect(offset).to be > size.call("bad-table-offset")
      expect(bytes.call("garbage").byteslice(0, 4)).not_to eq("\x00\x01\x00\x00".b)
    end
  end

  describe "derived fonts have the properties they claim" do
    let(:derived_path) { ->(id) { CorpusSpecHelper.path_of(root, by_id.fetch(id)) } }

    it "has a TTC with more than two members" do
      bytes = File.binread(derived_path.call("ttc-4members-shared"))
      expect(CorpusSfnt.parse_ttc(bytes).size).to eq(4)
    end

    it "has a WOFF2 collection (wOF2 signature with ttcf flavor)" do
      head = File.binread(derived_path.call("woff2-collection-4members"), 8)
      expect(head.byteslice(0, 4)).to eq("wOF2")
      expect(head.byteslice(4, 4)).to eq("ttcf")
    end

    it "has zero-length tables in the empty-table fonts" do
      %w[quirk-empty-optional-tables quirk-empty-name-table quirk-empty-cmap-table].each do |id|
        expect(CorpusSpecHelper.tables(derived_path.call(id)).values.map(&:bytesize)).to include(0)
      end
    end

    it "has non-ASCII Mac and Windows name records" do
      name = ->(id) { CorpusSpecHelper.tables(derived_path.call(id)).fetch("name") }
      records = lambda do |id|
        data = name.call(id)
        count, str_off = data.unpack("@2n2")
        Array.new(count) do |i|
          pid, _eid, _lid, _nid, len, off = data.byteslice(6 + (i * 12), 12).unpack("n6")
          [pid, data.byteslice(str_off + off, len)]
        end
      end
      mac = records.call("names-mac-roman-only").select { |pid, _| pid == 1 }
      expect(mac.any? { |_, s| s.bytes.any? { |b| b >= 0x80 } }).to be(true)
      win = records.call("names-windows-nonascii-only").select { |pid, _| pid == 3 }
      expect(win.any? { |_, s| s.unpack("n*").any? { |u| u > 0x7F } }).to be(true)
    end

    it "has the version quirks" do
      expect(File.binread(derived_path.call("quirk-sfnt-version-true"), 4)).to eq("true")
      expect(File.binread(derived_path.call("quirk-sfnt-version-otto-on-glyf"), 4)).to eq("OTTO")
      expect(CorpusSpecHelper.tables(derived_path.call("quirk-os2-version-0")).fetch("OS/2").unpack1("n")).to eq(0)
      expect(CorpusSpecHelper.tables(derived_path.call("quirk-head-version-2")).fetch("head").unpack1("n")).to eq(2)
      expect(CorpusSpecHelper.tables(derived_path.call("quirk-name-format-1")).fetch("name").unpack1("n")).to eq(1)
    end
  end

  describe "fetched source fonts have the properties they claim" do
    fetched = lambda do |tag|
      fonts.select { |f| f["type"] == "source" && f["tier"] == "ci" && f["covers"].include?(tag) }
    end
    check = lambda do |tag, &block|
      list = fetched.call(tag)
      list.each do |entry|
        path = CorpusSpecHelper.path_of(root, entry)
        skip "run `rake corpus:fetch` first (#{entry['id']} not fetched)" unless File.exist?(path)
        block.call(entry, path)
      end
    end

    axes = lambda do |path|
      fvar = CorpusSpecHelper.tables(path).fetch("fvar")
      axes_off, count, size, inst = fvar.unpack("@4n @8n n n")
      tags = Array.new(count) { |i| fvar.byteslice(axes_off + (i * size), 4) }
      [tags, inst]
    end

    it("hinted TTFs carry fpgm and prep") do
      check.call("static-ttf-hinted") { |_e, p| expect(CorpusSpecHelper.tables(p).keys).to include("fpgm", "prep") }
    end

    it("OTFs are CFF flavoured") do
      check.call("static-otf-small") { |_e, p| expect(File.binread(p, 4)).to eq("OTTO") }
    end

    it("large static fonts are at least 3 MB (decimal)") do
      %w[static-ttf-large static-otf-large].each do |tag|
        check.call(tag) { |e, _p| expect(e["size"]).to be >= 3_000_000 }
      end
    end

    it("variable fonts carry fvar, gvar and HVAR") do
      check.call("vf-fvar-gvar-hvar") { |_e, p| expect(CorpusSpecHelper.tables(p).keys).to include("fvar", "gvar", "HVAR") }
    end

    it("named-instance fonts have the axis and instances they claim") do
      check.call("vf-named-weight") do |_e, p|
        tags, inst = axes.call(p)
        expect(tags).to include("wght")
        expect(inst).to be > 0
      end
      check.call("vf-named-width") do |_e, p|
        tags, inst = axes.call(p)
        expect(tags).to include("wdth")
        expect(inst).to be > 0
      end
    end

    it("italic named-instance fonts are italic") do
      check.call("vf-named-italic") do |_e, p|
        t = CorpusSpecHelper.tables(p)
        axis_tags = axes.call(p).first
        italic_style = (t.fetch("head").unpack1("@44n") & 0x2) != 0
        expect(axis_tags.include?("ital") || italic_style).to be(true)
      end
    end

    it("CFF2 fonts carry CFF2 and no glyf") do
      check.call("cff2") { |_e, p| expect(CorpusSpecHelper.tables(p).keys).to include("CFF2").and(satisfy { |k| !k.include?("glyf") }) }
    end

    it("TTC fixtures have two members") do
      check.call("ttc-2-members") { |_e, p| expect(CorpusSfnt.parse_ttc(File.binread(p)).size).to eq(2) }
    end

    it("WOFF and WOFF2 fixtures carry their signature") do
      check.call("woff") { |_e, p| expect(File.binread(p, 4)).to eq("wOFF") }
      check.call("woff2") { |_e, p| expect(File.binread(p, 4)).to eq("wOF2") }
    end

    it("routing fonts are not plain sfnt") do
      check.call("routing-dfont") { |_e, p| expect(File.binread(p, 4)).not_to match(/\A(true|OTTO|ttcf|wOFF)\z/) }
      check.call("routing-type1") { |_e, p| expect(File.binread(p, 2)).to(satisfy { |s| s == "%!" || s.bytes.first == 0x80 }) }
    end
  end
end
# rubocop:enable RSpec/LeakyLocalVariable
