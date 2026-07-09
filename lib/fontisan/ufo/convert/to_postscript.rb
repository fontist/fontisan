# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Convert
      # Shared logic for UFO → PostScript Type 1 (PFB or PFA).
      # Used by ToPfb and ToPfa below; not registered in
      # WRAPPER_FOR_FORMAT directly. Callers should use the
      # format-specific modules.
      module ToPostscript
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @param compiler [Symbol] :ttf (default) or :otf
        # @param generator_class [Class] Type1::PFBGenerator or Type1::PFAGenerator
        # @param ps_options [Hash] forwarded to the generator
        #   (encoding, upm_scale, convert_curves)
        # @return [String] the output_path
        def self.convert(ufo, output_path:, generator_class:, compiler: :ttf,
**ps_options)
          compiler_class = Convert::COMPILER_FOR_FORMAT[compiler.to_sym]
          unless compiler_class
            raise ArgumentError,
                  "unknown intermediate compiler: #{compiler.inspect}"
          end

          Dir.mktmpdir do |dir|
            intermediate_path = File.join(dir,
                                          "intermediate#{ext_for(compiler)}")
            compiler_class.new(ufo).compile(output_path: intermediate_path)

            loaded = Fontisan::FontLoader.load(intermediate_path)
            bytes = generator_class.generate(loaded, ps_options)
            File.binwrite(output_path, bytes)
          end

          output_path
        end

        def self.ext_for(compiler)
          %i[otf otf2].include?(compiler) ? ".otf" : ".ttf"
        end
        private_class_method :ext_for
      end

      # UFO → PostScript Type 1 Binary (.pfb).
      module ToPfb
        def self.convert(ufo, output_path:, **)
          ToPostscript.convert(ufo, output_path: output_path,
                                    generator_class: Fontisan::Type1::PFBGenerator, **)
        end
      end

      # UFO → PostScript Type 1 ASCII (.pfa).
      module ToPfa
        def self.convert(ufo, output_path:, **)
          ToPostscript.convert(ufo, output_path: output_path,
                                    generator_class: Fontisan::Type1::PFAGenerator, **)
        end
      end
    end
  end
end
