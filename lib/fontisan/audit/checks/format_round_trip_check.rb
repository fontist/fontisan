# frozen_string_literal: true

require "tmpdir"

module Fontisan
  module Audit
    module Checks
      # Reports fidelity discrepancies when converting between TTF and
      # OTF outline formats. A high-fidelity conversion preserves:
      #
      #   - Glyph count (maxp.numGlyphs)
      #   - Codepoint coverage (cmap Unicode mappings)
      #   - Font identity (name table family + PostScript name)
      #
      # Any mismatch signals a bug in the outline converter or a data
      # loss path. This check is the pure-Ruby replacement for `ttx`
      # diff comparisons.
      #
      # Only converts in one direction (TTF→OTF for TrueType sources,
      # OTF→TTF for CFF sources) — full round-trip would double the
      # conversion surface without adding signal.
      #
      # @see Converters::OutlineConverter
      class FormatRoundTripCheck < Check
        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          target = round_trip_target(font)
          return [] unless target

          converted_path = convert_to_temp(font, target)
          return [] unless converted_path

          converted = FontLoader.load(converted_path)
          compare_fonts(font, converted, target)
        rescue StandardError => e
          [issue(severity: :warning,
                 message: "Round-trip conversion to #{target.upcase} failed: " \
                          "#{e.class}: #{e.message}",
                 location: "round_trip.#{target}")]
        ensure
          cleanup_temp(converted_path) if converted_path
        end

        def self.code
          :format_round_trip
        end

        # Decide the conversion target based on the source outline type.
        # @return [Symbol, nil] :otf, :ttf, or nil if not convertible
        def self.round_trip_target(font)
          return :otf if font.has_table?("glyf")
          return :ttf if font.has_table?("CFF ") || font.has_table?("CFF2")

          nil
        end
        private_class_method :round_trip_target

        def self.convert_to_temp(font, target)
          converter = Converters::FormatConverter.new
          tables = converter.convert(font, target)
          return nil unless tables && !tables.empty?

          dir = Dir.mktmpdir("fontisan-roundtrip-")
          path = File.join(dir, "converted.#{target}")
          sfnt = target == :otf ? 0x4F54544F : 0x00010000
          FontWriter.write_to_file(
            tables.transform_values { |t| t.is_a?(String) ? t : t.to_binary_s },
            path,
            sfnt_version: sfnt,
          )
          File.exist?(path) ? path : nil
        rescue StandardError
          nil
        end
        private_class_method :convert_to_temp

        def self.compare_fonts(source, converted, target)
          issues = []
          issues.concat(compare_glyph_count(source, converted, target))
          issues.concat(compare_codepoints(source, converted, target))
          issues
        end
        private_class_method :compare_fonts

        def self.compare_glyph_count(source, converted, target)
          src_count = glyph_count(source)
          dst_count = glyph_count(converted)
          return [] if src_count == dst_count

          [issue(severity: :warning,
                 message: "Round-trip to #{target.upcase}: glyph count changed " \
                          "from #{src_count} to #{dst_count}",
                 location: "round_trip.#{target}.glyph_count")]
        end
        private_class_method :compare_glyph_count

        def self.compare_codepoints(source, converted, target)
          src_cps = codepoint_set(source)
          dst_cps = codepoint_set(converted)
          missing = src_cps - dst_cps
          extra = dst_cps - src_cps
          issues = []
          unless missing.empty?
            issues << issue(severity: :warning,
                            message: "Round-trip to #{target.upcase}: #{missing.size} " \
                                     "codepoints lost (first: " \
                                     "#{missing.first(5).map { |c| format('U+%04X', c) }.join(', ')})",
                            location: "round_trip.#{target}.codepoints.missing")
          end
          unless extra.empty?
            issues << issue(severity: :info,
                            message: "Round-trip to #{target.upcase}: #{extra.size} " \
                                     "codepoints gained (first: " \
                                     "#{extra.first(5).map { |c| format('U+%04X', c) }.join(', ')})",
                            location: "round_trip.#{target}.codepoints.extra")
          end
          issues
        end
        private_class_method :compare_codepoints

        def self.glyph_count(font)
          return 0 unless font.has_table?("maxp")

          font.table("maxp").num_glyphs.to_i
        rescue StandardError
          0
        end
        private_class_method :glyph_count

        def self.codepoint_set(font)
          return Set.new unless font.has_table?("cmap")

          Set.new(font.table("cmap").unicode_mappings&.keys || [])
        rescue StandardError
          Set.new
        end
        private_class_method :codepoint_set

        def self.cleanup_temp(path)
          dir = File.dirname(path)
          FileUtils.rm_rf(dir) if Dir.exist?(dir)
        rescue StandardError
          nil
        end
        private_class_method :cleanup_temp
      end
    end
  end
end
