# frozen_string_literal: true

# Autoload hub for the Fontisan::Pipeline namespace.

module Fontisan
  module Pipeline
    autoload :FormatDetector, "fontisan/pipeline/format_detector"
    autoload :OutputWriter, "fontisan/pipeline/output_writer"
    autoload :Strategies, "fontisan/pipeline/strategies/base_strategy"
    autoload :TransformationPipeline, "fontisan/pipeline/transformation_pipeline"
    autoload :VariationResolver, "fontisan/pipeline/variation_resolver"
  end
end
