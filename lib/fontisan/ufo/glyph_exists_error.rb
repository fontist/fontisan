# frozen_string_literal: true

module Fontisan
  module Ufo
    # Raised by +Layer#add+ when a glyph with the same name is already
    # present. Surfaces what would otherwise be a silent overwrite so
    # the caller can decide between +Layer#put+ (intentional replace)
    # and +Stitcher::UniqueGlyphName.in+ (auto-rename).
    #
    # Extracted as a sibling of +Layer+ (rather than nested inside it)
    # so the namespace stays flat and the error can be referenced
    # without pulling in the full Layer implementation.
    class GlyphExistsError < StandardError
      attr_reader :name

      def initialize(name)
        @name = name
        super("a glyph named #{name.inspect} already exists; use #put " \
              "to overwrite or UniqueGlyphName.in to deconflict")
      end
    end
  end
end
