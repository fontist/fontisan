# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Style fields: weight, width, italic/bold flags, Panose family
      # classification.
      #
      # Returned fields:
      #   weight_class, width_class, italic, bold, panose
      #
      # Variable-font axis inventory lives in {Extractors::VariationDetail}
      # (MECE: this extractor is the OS/2 + head specialist, that one owns
      # everything fvar-derived).
      #
      # Delegates to {Audit::StyleExtractor} — the existing specialist
      # class that owns the OS/2 + head interpretation rules.
      class Style < Base
        def extract(context)
          style = StyleExtractor.new(context.font)
          {
            weight_class: style.weight_class,
            width_class: style.width_class,
            italic: style.italic,
            bold: style.bold,
            panose: style.panose,
          }
        end
      end
    end
  end
end
