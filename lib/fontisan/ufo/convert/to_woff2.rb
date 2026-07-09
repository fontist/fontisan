# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Convert
      # UFO → WOFF2. Same two-step pipeline as ToWoff, but with the
      # WOFF2 encoder (Brotli compression, optional glyf/loca
      # transforms) instead of WOFF (zlib).
      #
      # Returns the output_path; the WOFF2 binary itself lands at
      # +output_path+.
      module ToWoff2
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @param compiler [Symbol] which intermediate format to use:
        #   :ttf (default) or :otf
        # @param woff2_options [Hash] forwarded to Woff2Encoder.convert
        #   (brotli_quality, transform_tables, quality legacy alias)
        # @return [String] the output_path
        def self.convert(ufo, output_path:, compiler: :ttf, **woff2_options)
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
            result = Fontisan::Converters::Woff2Encoder.new.convert(loaded,
                                                                    woff2_options)
            File.binwrite(output_path, result[:woff2_binary])
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
