# frozen_string_literal: true

module Fontisan
  module Commands
    # Validates the structural integrity of a TTC/OTC/dfont collection
    # (TODO 74). Complements {ValidateCommand}, which runs profile-based
    # checks against a single face. This command runs collection-level
    # checks: face count, per-face glyph cap, optional cmap-union size.
    #
    # Returns an integer exit code (0 = all checks passed, 1 = any check
    # failed) suitable for use as the CLI's exit status.
    #
    # The command is intentionally narrow: it does not subclass
    # {BaseCommand} (which eagerly loads a single font at construction
    # time) because the input here is a collection, not a single face.
    # It owns its own loading via {Collection::Reader}.
    class ValidateCollectionCommand
      # Per-check result. The +message+ is +nil+ on pass.
      #
      # @!attribute [r] name
      #   @return [Symbol] check identifier (:face_count, :glyph_cap, :cmap_union)
      # @!attribute [r] passed
      #   @return [Boolean]
      # @!attribute [r] message
      #   @return [String, nil] human-readable failure detail
      Check = Struct.new(:name, :passed, :message, keyword_init: true) do
        # Predicate form so callers can write +check.passed?+ instead of
        # +check.passed+. Struct does not provide the +?+ suffix
        # automatically.
        def passed?
          passed
        end
      end

      DEFAULT_MAX_GLYPHS = 65_535

      # @param input [String] path to a TTC/OTC/dfont
      # @param expected_faces [Integer, nil] required face count, or nil to skip
      # @param max_glyphs [Integer] per-face glyph cap (default 65,535)
      # @param expected_cmap_union [Integer, nil] minimum cmap-union size, or nil to skip
      def initialize(input:, expected_faces: nil, max_glyphs: DEFAULT_MAX_GLYPHS,
                     expected_cmap_union: nil)
        @input = input
        @expected_faces = expected_faces
        @max_glyphs = max_glyphs
        @expected_cmap_union = expected_cmap_union
      end

      # @return [Integer] 0 if all checks passed, 1 otherwise
      def run
        reader = Collection::Reader.open(@input)
        @checks = [
          check_face_count(reader),
          check_glyph_cap(reader),
          check_cmap_union(reader),
        ].compact

        render_report(reader)
        @checks.all?(&:passed?) ? 0 : 1
      end

      # @return [Array<Check>] the most recent run's checks
      attr_reader :checks

      private

      def check_face_count(reader)
        return nil unless @expected_faces

        actual = reader.face_count
        passed = actual == @expected_faces
        Check.new(
          name: :face_count,
          passed: passed,
          message: passed ? nil : "expected #{@expected_faces} faces, got #{actual}",
        )
      end

      def check_glyph_cap(reader)
        over = reader.stats.select { |s| s.glyph_count > @max_glyphs }
        Check.new(
          name: :glyph_cap,
          passed: over.empty?,
          message: if over.empty?
                     nil
                   else
                     "faces over cap: #{over.map do |s|
                       "##{s.index}=#{s.glyph_count}"
                     end.join(', ')}"
                   end,
        )
      end

      def check_cmap_union(reader)
        return nil unless @expected_cmap_union

        actual = reader.cmap_union.size
        passed = actual >= @expected_cmap_union
        Check.new(
          name: :cmap_union,
          passed: passed,
          message: passed ? nil : "cmap union #{actual} < expected #{@expected_cmap_union}",
        )
      end

      # Default rendering. Callers wanting structured output can
      # instantiate the command, call +#run+, then read +#checks+
      # directly instead of relying on stdout.
      def render_report(reader)
        reader.stats.each do |s|
          marker = s.glyph_count <= @max_glyphs ? "✓" : "✗"
          puts format("face %<index>d: %<glyphs>7d glyphs %<marker>s",
                      index: s.index, glyphs: s.glyph_count, marker: marker)
        end
        puts "all #{reader.face_count} faces within #{@max_glyphs}-glyph cap ✓"

        @checks.each do |check|
          if check.passed?
            puts "#{check.name}: ✓"
          else
            puts "#{check.name}: ✗ (#{check.message})"
          end
        end
      end
    end
  end
end
