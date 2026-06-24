# frozen_string_literal: true

# Autoload hub for the Fontisan::Variation namespace.

module Fontisan
  module Variation
    autoload :BlendApplier, "fontisan/variation/blend_applier"
    autoload :Cache, "fontisan/variation/cache"
    autoload :CacheKeyBuilder, "fontisan/variation/cache_key_builder"
    autoload :Converter, "fontisan/variation/converter"
    autoload :DataExtractor, "fontisan/variation/data_extractor"
    autoload :DeltaApplier, "fontisan/variation/delta_applier"
    autoload :DeltaParser, "fontisan/variation/delta_parser"
    autoload :Inspector, "fontisan/variation/inspector"
    autoload :InstanceGenerator, "fontisan/variation/instance_generator"
    autoload :InstanceWriter, "fontisan/variation/instance_writer"
    autoload :Interpolator, "fontisan/variation/interpolator"
    autoload :MetricsAdjuster, "fontisan/variation/metrics_adjuster"
    autoload :Optimizer, "fontisan/variation/optimizer"
    autoload :ParallelGenerator, "fontisan/variation/parallel_generator"
    autoload :RegionMatcher, "fontisan/variation/region_matcher"
    autoload :Subsetter, "fontisan/variation/subsetter"
    autoload :TableAccessor, "fontisan/variation/table_accessor"
    autoload :ThreadSafeCache, "fontisan/variation/cache"
    autoload :TupleVariationHeader, "fontisan/variation/tuple_variation_header"
    autoload :Validator, "fontisan/variation/validator"
    autoload :VariableSvgGenerator, "fontisan/variation/variable_svg_generator"
    autoload :VariationContext, "fontisan/variation/variation_context"
    autoload :VariationPreserver, "fontisan/variation/variation_preserver"
  end
end
