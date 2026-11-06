# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module FontisanBench
  # One benchmarked operation. `requires` lists the constants the measured
  # fontisan must define; an operation the measured tree cannot run is
  # skipped, which the comparison reports as "new" (it has no base number).
  Op = Struct.new(:name, :description, :requires, :body, keyword_init: true)

  # The #157 operations, run against the `ci` tier of the reference corpus
  # (corpus/fonts, fetched by `rake corpus:fetch`).
  #
  # Table parse, names, cmap, instancing and conversion call the classes the
  # reference facade wraps, so the same code runs on a base that predates
  # `Fontisan::Reference`; audit, audit_dir and scan go through the facade.
  class Ops
    SS_TTF = "source-sans-3-regular-ttf/SourceSans3-Regular.ttf"
    SS_OTF = "source-sans-3-regular-otf/SourceSans3-Regular.otf"
    SS_WOFF = "source-sans-3-regular-ttf-woff/SourceSans3-Regular.ttf.woff"
    SS_WOFF2 = "source-sans-3-regular-ttf-woff2/SourceSans3-Regular.ttf.woff2"
    SS_VF = "source-sans-3-vf-upright-ttf/SourceSans3VF-Upright.ttf"
    NOTO = "noto-sans-hinted-regular/NotoSans-Regular.ttf"
    TABLE_PARSE_FONTS = [SS_TTF, SS_OTF, NOTO].freeze
    NAME_FONTS = [SS_TTF, SS_OTF, SS_VF, NOTO].freeze

    attr_reader :corpus

    def initialize(corpus)
      @corpus = File.expand_path(corpus)
      @fonts_dir = File.join(@corpus, "fonts")
    end

    def all
      [table_parse, hmtx_metrics, names, cmap_coverage, audit_file, audit_dir, scan,
       vf_instance, woff2_decode, convert_roundtrip, woff2_encode]
    end

    def scan_paths
      Dir.glob(File.join(@fonts_dir, "**", "*")).select { |f| File.file?(f) }.sort
    end

    private

    def font(rel)
      File.join(@fonts_dir, rel)
    end

    def load_full(rel)
      Fontisan::FontLoader.load(font(rel), mode: :full, lazy: false)
    end

    def op(name, description, requires: [], &body)
      Op.new(name: name, description: description, requires: requires, body: body)
    end

    def table_parse
      op("table_parse", "load (full) and parse every table of 3 static fonts") do
        TABLE_PARSE_FONTS.each do |rel|
          f = load_full(rel)
          f.table_names.each { |tag| f.table(tag) }
        end
      end
    end

    # Tables::Hmtx#metric_for is the per-glyph metric lookup; table_parse only
    # parses the table, so a slowdown inside the lookup was invisible.
    def hmtx_metrics
      op("hmtx_metrics", "hmtx metric_for every glyph of 3 static fonts") do
        TABLE_PARSE_FONTS.each do |rel|
          f = load_full(rel)
          hmtx = f.table("hmtx")
          hmtx.parse_with_context(f.table("hhea").number_of_h_metrics, f.table("maxp").num_glyphs) unless hmtx.parsed?
          f.table("maxp").num_glyphs.times { |gid| hmtx.metric_for(gid) }
        end
      end
    end

    def names
      op("names", "name table: full, family, subfamily, postscript, 4 fonts") do
        ids = [Fontisan::Tables::Name::FULL_NAME, Fontisan::Tables::Name::FAMILY,
               Fontisan::Tables::Name::SUBFAMILY, Fontisan::Tables::Name::POSTSCRIPT_NAME]
        NAME_FONTS.each do |rel|
          f = Fontisan::FontLoader.load(font(rel), mode: :metadata)
          name = f.table("name")
          ids.each { |id| name.english_name(id) }
        end
      end
    end

    def cmap_coverage
      op("cmap_coverage", "cmap unicode mappings of 3 static fonts") do
        TABLE_PARSE_FONTS.each do |rel|
          load_full(rel).table("cmap").unicode_mappings.size
        end
      end
    end

    def audit_file
      op("audit_file", "audit with validation, one font (facade)", requires: ["Fontisan::Reference"]) do
        Fontisan::Reference.audit(font(SS_TTF), validate: true)
      end
    end

    def audit_dir
      op("audit_dir", "audit every file of the ci corpus directory (facade)",
         requires: ["Fontisan::Reference"]) do
        Fontisan::Reference.audit_dir(@fonts_dir, validate: false)
      end
    end

    def scan
      op("scan_dir", "scan rows for every file of the ci corpus directory (facade)",
         requires: ["Fontisan::Reference"]) do
        Fontisan::Reference.scan(scan_paths)
      end
    end

    def vf_instance
      op("vf_instance", "variable font instance at wght=700") do
        Fontisan::Variable::Instancer.new(load_full(SS_VF)).instance({ "wght" => 700.0 })
      end
    end

    def woff2_decode
      op("woff2_decode", "load a WOFF2 and parse every table") do
        f = load_full(SS_WOFF2)
        f.table_names.each { |tag| f.table(tag) }
      end
    end

    def convert_roundtrip
      op("convert_roundtrip", "ttf -> woff -> ttf") do
        Dir.mktmpdir("fontisan-bench") do |dir|
          Fontisan.convert(font(SS_TTF), to: :woff, output: File.join(dir, "a.woff"), quiet: true)
          Fontisan.convert(File.join(dir, "a.woff"), to: :ttf, output: File.join(dir, "b.ttf"), quiet: true)
        end
      end
    end

    def woff2_encode
      op("woff2_encode", "ttf -> woff2") do
        Dir.mktmpdir("fontisan-bench") do |dir|
          Fontisan.convert(font(SS_TTF), to: :woff2, output: File.join(dir, "a.woff2"), quiet: true)
        end
      end
    end
  end
end
