# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Path
      # A single parsed SVG path command.
      #
      # @attr type [Symbol] one of :M, :L, :H, :V, :C, :S, :Q, :T, :Z
      # @attr absolute [Boolean] true for uppercase (absolute), false for lowercase (relative)
      # @attr args [Array<Float>] the numeric arguments in order
      Command = Struct.new(:type, :absolute, :args, keyword_init: true) do
        def relative?
          !absolute
        end
      end
    end
  end
end
