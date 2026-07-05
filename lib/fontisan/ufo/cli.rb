# frozen_string_literal: true

require "thor"

module Fontisan
  module Ufo
    # CLI subcommand for UFO source operations.
    #
    #   fontisan ufo build font.ufo --output out.ttf [--format otf]
    #   fontisan ufo convert font.ttf font.ufo
    #   fontisan ufo validate font.ufo
    class Cli < Thor
      desc "build UFO", "Compile a UFO source to a binary font"
      method_option :output, type: :string, required: true,
                             desc: "Output file path"
      method_option :to, type: :string, default: "ttf",
                         desc: "Output format (ttf, otf, or otf2)"
      def build(ufo)
        font = Font.open(ufo)
        format = (options[:to] || "ttf").to_s.downcase.to_sym
        Convert.convert(font, to: format, output_path: options[:output])
        puts "wrote #{options[:output]} (#{File.size(options[:output])} bytes)"
      rescue ArgumentError => e
        warn e.message
        exit 1
      rescue Errno::ENOENT
        warn "UFO not found: #{ufo}"
        exit 1
      end

      desc "convert INPUT OUTPUT", "Convert between UFO and binary formats"
      method_option :to, type: :string,
                         desc: "Override format detection (ttf, otf, otf2, ufo)"
      def convert(input, output)
        if ufo?(input)
          font = Font.open(input)
          format = options[:to] || File.extname(output).delete(".").downcase
          Convert.convert(font, to: format.to_sym, output_path: output)
        else
          # Binary → UFO
          loaded = Fontisan::FontLoader.load(input)
          ufo = Convert::FromBinData.convert(loaded)
          Writer.new(ufo).write(output)
        end
        puts "wrote #{output}"
      rescue ArgumentError => e
        warn e.message
        exit 1
      end

      desc "validate UFO", "Check a UFO source for structural issues"
      def validate(ufo)
        font = Font.open(ufo)
        issues = []
        issues << "no glyphs in default layer" if font.glyphs.empty?
        issues << "no family name" unless font.info.family_name
        issues << "unitsPerEm not set" unless font.info.units_per_em
        issues << "missing .notdef glyph" unless font.glyph(".notdef")

        if issues.empty?
          puts "OK  #{ufo}"
        else
          issues.each { |i| warn "FAIL  #{i}" }
          exit 1
        end
      end

      private

      def ufo?(path)
        File.directory?(path) && File.exist?(File.join(path, "fontinfo.plist"))
      end
    end
  end
end
