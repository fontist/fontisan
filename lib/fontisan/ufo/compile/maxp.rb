# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Builds the OpenType `maxp` (maximum profile) table.
      # TrueType (0x00010000) carries 13 metrics; CFF (0x00005000)
      # carries just num_glyphs. We pick the version based on which
      # outline compiler is in use — caller passes `version:`.
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/maxp
      module Maxp
        VERSION_TRUE_TYPE = 0x00010000
        VERSION_OPEN_TYPE = 0x00005000

        # @param _font [Fontisan::Ufo::Font]
        # @param glyphs [Array<Fontisan::Ufo::Glyph>]
        # @param version [Integer] one of VERSION_TRUE_TYPE / VERSION_OPEN_TYPE
        # @return [Fontisan::Tables::Maxp]
        def self.build(_font, glyphs:, version: VERSION_OPEN_TYPE)
          if version == VERSION_TRUE_TYPE
            build_truetype(glyphs)
          else
            Fontisan::Tables::Maxp.new(
              version_raw: VERSION_OPEN_TYPE,
              num_glyphs: glyphs.size,
            )
          end
        end

        def self.build_truetype(glyphs)
          max_points = glyphs.map(&:point_count).max || 0
          max_contours = glyphs.map { |g| g.contours.size }.max || 0
          max_components = glyphs.map { |g| g.components.size }.max || 0

          Fontisan::Tables::Maxp.new(
            version_raw: VERSION_TRUE_TYPE,
            num_glyphs: glyphs.size,
            max_points: max_points,
            max_contours: max_contours,
            max_composite_points: max_points,
            max_composite_contours: max_contours,
            max_zones: 2,
            max_twilight_points: 0,
            max_storage: 0,
            max_function_defs: 0,
            max_instruction_defs: 0,
            max_stack_elements: 0,
            max_size_of_instructions: 0,
            max_component_elements: max_components,
            max_component_depth: max_components.positive? ? 1 : 0,
          )
        end
        private_class_method :build_truetype
      end
    end
  end
end
