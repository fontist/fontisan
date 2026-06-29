# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Selectors decide which glyphs from a source to include in the
    # stitched font. Each selector appends to the Stitcher's bindings
    # list. OCP: adding a new way to select = adding a new Selector
    # class + a registry entry.
    module Selector
      autoload :Range,      "fontisan/stitcher/selector/range"
      autoload :Codepoints, "fontisan/stitcher/selector/codepoints"
      autoload :Gid,        "fontisan/stitcher/selector/gid"

      REGISTRY = {
        range: Range,
        codepoints: Codepoints,
        gid: Gid,
      }.freeze

      def self.resolve(name)
        REGISTRY[name.to_sym] or
          raise ArgumentError, "unknown selector: #{name.inspect}"
      end
    end
  end
end
