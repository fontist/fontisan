# frozen_string_literal: true

module Fontisan
  module Commands
    # Resolves the on-disk output path for each target format in a
    # multi-format conversion (TODO 72).
    #
    # Rules:
    #   - One format + path has extension → use the path as-is.
    #   - One format + path has no extension → append ".<format>".
    #   - Many formats + path has extension → +ArgumentError+ (ambiguous).
    #   - Many formats + path has no extension → append ".<format>" per target.
    #
    # Pure value object: no I/O, no mutation. Extracted from
    # {ConvertCommand} so multi-format path resolution can be tested
    # independently of the transformation pipeline.
    class MultiFormatOutput
      # @param base_path [String] user-supplied --output value
      # @param target_formats [Array<Symbol>] non-empty, deduplicated
      def initialize(base_path, target_formats)
        @base_path = base_path
        @target_formats = target_formats
      end

      # @return [Array<String>] one resolved path per target format,
      #   in the same order as +target_formats+
      # @raise [ArgumentError] if the base path is ambiguous
      def paths
        single? ? [single_format_path] : multi_format_paths
      end

      private

      def single?
        @target_formats.size == 1
      end

      def single_format_path
        has_extension? ? @base_path : "#{@base_path}.#{@target_formats.first}"
      end

      def multi_format_paths
        if has_extension?
          raise ArgumentError,
                "Output path #{@base_path.inspect} has an extension but " \
                "#{@target_formats.size} target formats were given " \
                "(#{@target_formats.join(', ')}). Drop the extension or " \
                "specify a single format."
        end

        @target_formats.map { |fmt| "#{@base_path}.#{fmt}" }
      end

      def has_extension?
        !File.extname(@base_path).strip.downcase.empty?
      end
    end
  end
end
