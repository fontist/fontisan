# frozen_string_literal: true

module Fontisan
  module Ufo
    # A single outline point. UFO's `point` element has:
    #   - x, y          (Float, font units)
    #   - type          (one of "move", "line", "offcurve", "curve", "qcurve")
    #   - smooth        (Bool, optional)
    #
    # "offcurve" is the UFO 1/2 name; UFO 3 uses "qcurve". Both are
    # accepted on read.
    class Point
      attr_reader :x, :y, :type, :smooth

      def initialize(x:, y:, type:, smooth: false)
        @x = x
        @y = y
        @type = type.to_s
        @smooth = smooth
      end

      def on_curve?
        @type == "line" || @type == "move" || @type == "curve"
      end

      def off_curve?
        @type == "offcurve" || @type == "qcurve"
      end

      # @return [Hash] suitable for `to_glif` output
      def to_h
        h = { x: @x, y: @y, type: @type }
        h[:smooth] = true if @smooth
        h
      end
    end
  end
end
