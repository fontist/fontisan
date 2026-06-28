# frozen_string_literal: true

module Fontisan
  module FontBuilder
    # Per-table serialization namespace. Each table is its own class
    # under Tables::*. The Assembler picks the right set based on
    # +format: (:ttf or :otf)+ and writes them in canonical order.
    module Tables
      autoload :Assembler, "fontisan/font_builder/tables/assembler"
      autoload :Head, "fontisan/font_builder/tables/head"
    end
  end
end
