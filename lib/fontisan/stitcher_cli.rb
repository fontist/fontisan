# frozen_string_literal: true

require "thor"

module Fontisan
  # CLI subcommand for multi-source font stitching.
  #
  #   fontisan stitch --source latin=PATH --source jp=PATH \
  #     --output out.ttf \
  #     --include-range latin=0x41-0x5A \
  #     --include-range jp=0x3040-0x309F
  class StitcherCli < Thor
    desc "stitch", "Stitch glyphs from multiple sources into one font"
    method_option :source, type: :array, required: true,
                           desc: "Named source (name=path); repeatable"
    method_option :include_range, type: :array, default: [],
                                  desc: "Range to include (name=hex-hex); repeatable"
    method_option :include_codepoints, type: :array, default: [],
                                       desc: "Codepoint list (name=hex,hex,...); repeatable"
    method_option :notdef_from, type: :string,
                                desc: "Source label to take .notdef from"
    method_option :output, type: :string, required: true,
                           desc: "Output file path"
    method_option :to, type: :string, default: "ttf",
                       desc: "Output format (ttf or otf)"

    def stitch
      stitcher = Stitcher.new

      options[:source].each do |spec|
        label, path = spec.split("=", 2)
        font = load_source(path)
        stitcher.add_source(label, font)
      end

      options[:include_range]&.each do |spec|
        label, range_str = spec.split("=", 2)
        lo, hi = parse_range(range_str)
        stitcher.include_range(lo..hi, from: label)
      end

      options[:include_codepoints]&.each do |spec|
        label, cps_str = spec.split("=", 2)
        cps = cps_str.split(",").map { |h| Integer(h) }
        stitcher.include_codepoints(cps, from: label)
      end

      stitcher.include_notdef(from: options[:notdef_from]) if options[:notdef_from]

      stitcher.write_to(options[:output], format: options[:to].to_sym)
      puts "wrote #{options[:output]} (#{File.size(options[:output])} bytes)"
    end

    private

    def load_source(path)
      if File.directory?(path) && File.exist?(File.join(path, "fontinfo.plist"))
        Ufo::Font.open(path)
      else
        FontLoader.load(path)
      end
    end

    def parse_range(str)
      lo, hi = str.split("-", 2)
      [Integer(lo), Integer(hi)]
    end
  end
end
