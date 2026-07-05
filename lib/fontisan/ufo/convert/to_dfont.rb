# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Convert
      # UFO → dfont (Mac OS resource-fork font container). Two-step:
      #
      #   1. Compile UFO → TTF/OTF in tmpdir.
      #   2. Load + feed to Collection::DfontBuilder, which wraps the
      #      SFNT binary in a Mac resource fork.
      module ToDfont
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @param compiler [Symbol] :ttf (default) or :otf
        # @return [String] the output_path
        def self.convert(ufo, output_path:, compiler: :ttf, **_opts)
          compiler_class = Convert::COMPILER_FOR_FORMAT[compiler.to_sym]
          raise ArgumentError, "unknown intermediate compiler: #{compiler.inspect}" unless compiler_class

          Dir.mktmpdir do |dir|
            intermediate_path = File.join(dir, "intermediate#{ext_for(compiler)}")
            compiler_class.new(ufo).compile(output_path: intermediate_path)

            loaded = Fontisan::FontLoader.load(intermediate_path)
            result = Fontisan::Collection::DfontBuilder.new([loaded]).build
            File.binwrite(output_path, result[:binary])
          end

          output_path
        end

        def self.ext_for(compiler)
          %i[otf otf2].include?(compiler) ? ".otf" : ".ttf"
        end
        private_class_method :ext_for
      end
    end
  end
end
