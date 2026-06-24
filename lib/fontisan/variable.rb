# frozen_string_literal: true

# Autoload hub for the Fontisan::Variable namespace.

module Fontisan
  module Variable
    autoload :AxisNormalizer, "fontisan/variable/axis_normalizer"
    autoload :DeltaApplicator, "fontisan/variable/delta_applicator"
    autoload :GlyphDeltaProcessor, "fontisan/variable/glyph_delta_processor"
    autoload :Instancer, "fontisan/variable/instancer"
    autoload :MetricDeltaProcessor, "fontisan/variable/metric_delta_processor"
    autoload :RegionMatcher, "fontisan/variable/region_matcher"
    autoload :StaticFontBuilder, "fontisan/variable/static_font_builder"
    autoload :TableUpdater, "fontisan/variable/table_updater"
  end
end
