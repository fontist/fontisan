# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      module FeatureWriters
        # Value object returned by every feature writer's +#write+
        # method. Carries the structured data the corresponding
        # table builder needs to encode the binary subtable.
        #
        # Writers return +nil+ instead when the UFO has no data for
        # the feature — the compiler skips +nil+ outputs.
        FeatureOutput = Struct.new(
          :table_tag, # "GPOS", "GSUB", "GDEF"
          :feature_tag, # "kern", "mark", "curs", etc. (nil for GDEF)
          :lookup_type, # Integer GSUB/GPOS lookup type
          :data,        # Hash — writer-specific structure
          keyword_init: true,
        ) do
          def table_tag
            self[:table_tag]
          end

          def feature_tag
            self[:feature_tag]
          end

          def lookup_type
            self[:lookup_type]
          end

          def data
            self[:data]
          end
        end

        # Abstract base class for feature writers. Concrete writers
        # (Kern, Gdef, Mark, etc.) extend this and implement +#write+.
        class Base
          attr_reader :font

          # @param font [Fontisan::Ufo::Font] the UFO source
          def initialize(font)
            @font = font
          end

          # @return [FeatureOutput, nil] structured data for the
          #   feature, or +nil+ if the UFO has nothing for it
          def write
            raise NotImplementedError, "#{self.class} must implement #write"
          end
        end
      end
    end
  end
end
