# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Style fields: weight, width, italic/bold flags, Panose family
      # classification, and variable-font axis inventory.
      #
      # Returned fields:
      #   weight_class, width_class, italic, bold, panose,
      #   is_variable, axes
      #
      # Delegates to {Audit::StyleExtractor} — the existing specialist
      # class that owns the OS/2 + head + fvar interpretation rules.
      class Style < Base
        def extract(context)
          style = StyleExtractor.new(context.font)
          {
            weight_class: style.weight_class,
            width_class: style.width_class,
            italic: style.italic,
            bold: style.bold,
            panose: style.panose,
            is_variable: style.variable?,
            axes: style.axes,
          }
        end
      end
    end
  end
end
