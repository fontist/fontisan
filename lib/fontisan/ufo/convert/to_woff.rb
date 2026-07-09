# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Convert
      # UFO → WOFF. Two-step pipeline:
      #
      #   1. Compile the UFO to a TTF (or OTF) in a tmpdir via the
      #      corresponding Compile::*Compiler.
      #   2. Load the compiled binary back via FontLoader, then run
      #      Converters::WoffWriter to wrap it in the WOFF container.
      #
      # The tmpfile is cleaned up automatically (Dir.mktmpdir block).
      # The original UFO is never mutated.
      #
      # Why two steps instead of one in-memory pass: the WOFF
      # encoders operate on a loaded font's table directory (they
      # need checksums, offsets, alignment), not on a UFO model.
      # Round-tripping through the compiled binary is the simplest
      # path; an in-memory variant would duplicate the table-bytes
      # extraction that FontLoader already does.
      module ToWoff
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @param compiler [Symbol] which intermediate format to use:
        #   :ttf (default) or :otf
        # @param woff_options [Hash] forwarded to WoffWriter.convert
        #   (zlib_level, uncompressed, compression_threshold,
        #   metadata_xml, etc.)
        # @return [String] the output_path
        def self.convert(ufo, output_path:, compiler: :ttf, **woff_options)
          compiler_class = Convert::COMPILER_FOR_FORMAT[compiler.to_sym]
          unless compiler_class
            raise ArgumentError,
                  "unknown intermediate compiler: #{compiler.inspect}"
          end

          Dir.mktmpdir do |dir|
            intermediate_path = File.join(dir,
                                          "intermediate#{format_ext(compiler)}")
            compiler_class.new(ufo).compile(output_path: intermediate_path)

            loaded = Fontisan::FontLoader.load(intermediate_path)
            woff_bytes = Fontisan::Converters::WoffWriter.new.convert(loaded,
                                                                      woff_options)
            File.binwrite(output_path, woff_bytes)
          end

          output_path
        end

        def self.format_ext(compiler)
          %i[otf otf2].include?(compiler) ? ".otf" : ".ttf"
        end
        private_class_method :format_ext
      end
    end
  end
end
