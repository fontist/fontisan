# frozen_string_literal: true

require "fontisan/font_builder/font_model"

module Fontisan
  module FontBuilder
    # Public entry point. Named Main because the parent module is
    # FontBuilder; this avoids Fontisan::FontBuilder::FontBuilder.
    # Consumers call Fontisan::FontBuilder::Main.new(...).
    class Main
      attr_reader :format, :model

      def initialize(format: :ttf)
        @format = format
        @model = FontModel.new
      end

      def set_cmap(unicode_map)
        unicode_map.each do |cp, gid|
          model.cmap[cp] = gid
          model.glyphs[gid] ||= GlyphEntry.new
        end
        model.invalidate_caches
      end

      def add_glyph(gid, outline:, metrics:)
        model.glyphs[gid] = GlyphEntry.new(outline: outline, metrics: metrics)
      end

      def set_name_records(records)
        model.names = records.dup
      end

      def set_version(version)
        model.font_version = version
      end

      def set_units_per_em(value)
        model.units_per_em = value
      end

      def write_to(path)
        Tables::Assembler.new(model, format: format).write(path)
      end
    end
  end
end
