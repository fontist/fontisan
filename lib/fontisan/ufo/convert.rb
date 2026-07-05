# frozen_string_literal: true

module Fontisan
  module Ufo
    # Conversion layer between the UFO model and fontisan's BinData
    # table layer. Two directions:
    #
    #   ToBinData / To{Format} .convert(ufo, output_path:) → writes file
    #   FromBinData.convert(loaded_font)                   → Ufo::Font
    #
    # The To* paths are thin facades over the corresponding
    # Compile::*Compiler classes. They exist to give callers a single
    # uniform convert API and to keep the CLI's format dispatch in
    # one data-driven place (COMPILER_FOR_FORMAT) instead of a switch
    # statement per CLI command.
    module Convert
      autoload :FromBinData, "fontisan/ufo/convert/from_bin_data"
      autoload :ToTtf, "fontisan/ufo/convert/to_ttf"
      autoload :ToOtf, "fontisan/ufo/convert/to_otf"
      autoload :ToOtf2, "fontisan/ufo/convert/to_otf2"
      autoload :ToWoff, "fontisan/ufo/convert/to_woff"
      autoload :ToWoff2, "fontisan/ufo/convert/to_woff2"

      # Single source of truth for "which compiler handles this
      # output format?". OCP: adding a format = adding one entry
      # here + one wrapper file. The CLI reads from this hash
      # instead of a case statement.
      COMPILER_FOR_FORMAT = {
        ttf: Compile::TtfCompiler,
        otf: Compile::OtfCompiler,
        otf2: Compile::Otf2Compiler,
      }.freeze

      # Wrapper modules for 2-step pipelines (UFO → compiler →
      # tmpfile → encoder → output). These don't fit the 1-step
      # COMPILER_FOR_FORMAT registry because they need a tmpdir +
      # a second encoder pass. OCP: adding a 2-step format =
      # adding one entry here + one wrapper file.
      WRAPPER_FOR_FORMAT = {
        woff: ToWoff,
        woff2: ToWoff2,
      }.freeze

      # Convert a UFO to a binary format, writing to +output_path+.
      # Routes through either COMPILER_FOR_FORMAT (1-step: ttf/otf/
      # otf2) or WRAPPER_FOR_FORMAT (2-step: woff/woff2). Raises
      # +ArgumentError+ for unknown formats.
      #
      # @param ufo [Fontisan::Ufo::Font]
      # @param to [Symbol] format key
      # @param output_path [String]
      # @param opts [Hash] forwarded to the compiler or wrapper
      #   (woff/woff2 wrappers take +compiler:+ + woff-specific opts)
      # @return [String] the output_path
      def self.convert(ufo, to:, output_path:, **)
        format_key = to.to_sym

        if (wrapper = WRAPPER_FOR_FORMAT[format_key])
          return wrapper.convert(ufo, output_path: output_path, **)
        end

        compiler = COMPILER_FOR_FORMAT[format_key]
        raise ArgumentError, "unknown UFO output format: #{to.inspect}" unless compiler

        compiler.new(ufo).compile(output_path: output_path)
        output_path
      end
    end
  end
end
