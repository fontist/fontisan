# frozen_string_literal: true

module Fontisan
  module Unicode
    # Unicode plane metadata. A plane is a contiguous range of 65,536
    # codepoints; +cp >> 16+ is the plane number.
    #
    # Plane labels follow the Unicode standard names. Unassigned planes
    # fall back to +"Plane_N"+. This is a pure-data module — no I/O, no
    # state, no dependency on tables or stitcher.
    module Plane
      BMP = 0
      SMP = 1
      SIP = 2
      TIP = 3
      SSP = 14

      # @param codepoint [Integer]
      # @return [Integer] plane number (0..16)
      def self.of(codepoint)
        codepoint >> 16
      end

      # @param plane [Integer]
      # @return [String] human-readable plane label
      def self.label(plane)
        case plane
        when BMP then "BMP"
        when SMP then "SMP"
        when SIP then "SIP"
        when TIP then "TIP"
        when SSP then "SSP"
        else "Plane_#{plane}"
        end
      end

      # @param codepoint [Integer]
      # @return [String] label of the plane containing +codepoint+
      def self.label_of(codepoint)
        label(of(codepoint))
      end
    end
  end
end
