# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Ufo
    module Convert
      # UFO → TrueType Collection (.ttc). Two-step:
      #
      #   1. Compile UFO → TTF in tmpdir.
      #   2. Load + feed to Collection::Builder with format: :ttc.
      #
      # A single UFO produces a single-face collection. Multi-face
      # collections from multiple UFOs are a separate concern (the
      # Stitcher pipeline handles that case).
      module ToTtc
        # @param ufo [Fontisan::Ufo::Font]
        # @param output_path [String]
        # @return [String] the output_path
        def self.convert(ufo, output_path:, **_opts)
          Dir.mktmpdir do |dir|
            intermediate_path = File.join(dir, "intermediate.ttf")
            Compile::TtfCompiler.new(ufo).compile(output_path: intermediate_path)

            loaded = Fontisan::FontLoader.load(intermediate_path)
            Fontisan::Collection::Builder.new([loaded], format: :ttc,
                                                        optimize: true).build_to_file(output_path)
          end

          output_path
        end
      end
    end
  end
end
