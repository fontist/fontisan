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
                         desc: "Output format (ttf or otf)"
      def build(ufo)
        font = Font.open(ufo)
        format_sym = (options[:to] || "ttf").to_s.downcase.to_sym
        compiler =
          case format_sym
          when :ttf then Compile::TtfCompiler
          when :otf then Compile::OtfCompiler
          else
            warn "unknown format: #{options[:to].inspect}"
            exit 1
          end
        compiler.new(font).compile(output_path: options[:output])
        puts "wrote #{options[:output]} (#{File.size(options[:output])} bytes)"
      rescue Errno::ENOENT
        warn "UFO not found: #{ufo}"
        exit 1
      end

      desc "convert INPUT OUTPUT", "Convert between UFO and binary formats"
      method_option :to, type: :string,
                         desc: "Override format detection (ttf, otf, ufo)"
      def convert(input, output)
        if ufo?(input)
          font = Font.open(input)
          format = options[:to] || File.extname(output).delete(".").downcase
          compiler =
            case format.to_sym
            when :ttf then Compile::TtfCompiler
            when :otf then Compile::OtfCompiler
            else
              warn "unsupported output format: #{format.inspect}"
              exit 1
            end
          compiler.new(font).compile(output_path: output)
        else
          warn "binary → UFO conversion not yet implemented (TODO.full/14)"
          exit 1
        end
        puts "wrote #{output}"
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
