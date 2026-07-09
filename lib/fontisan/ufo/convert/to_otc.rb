# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Convert
      # UFO → OpenType Collection (.otc). Two-step:
      #
      #   1. Compile UFO → OTF (CFF) in tmpdir.
      #   2. Load + feed to Collection::Builder with format: :otc.
      #
      # A single UFO produces a single-face collection.
      module ToOtc
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @param compiler [Symbol] :otf (default, CFF1) or :otf2 (CFF2)
        # @return [String] the output_path
        def self.convert(ufo, output_path:, compiler: :otf, **_opts)
          compiler_class = Convert::COMPILER_FOR_FORMAT[compiler.to_sym]
          unless compiler_class
            raise ArgumentError,
                  "unknown intermediate compiler: #{compiler.inspect}"
          end

          Dir.mktmpdir do |dir|
            intermediate_path = File.join(dir, "intermediate.otf")
            compiler_class.new(ufo).compile(output_path: intermediate_path)

            loaded = Fontisan::FontLoader.load(intermediate_path)
            Fontisan::Collection::Builder.new([loaded], format: :otc,
                                                        optimize: true).build_to_file(output_path)
          end

          output_path
        end
      end
    end
  end
end
