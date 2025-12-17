# frozen_string_literal: true

require_relative "../models/hint"

module Fontisan
  module Hints
    # Applies rendering hints to PostScript/CFF CharString data
    #
    # This applier converts universal Hint objects into PostScript hint
    # operators and integrates them into CharString data. It ensures proper
    # operator placement and maintains CharString validity.
    #
    # **PostScript Hint Placement:**
    #
    # - Stem hints (hstem/vstem) must appear at the beginning
    # - Hintmask operators can appear throughout the CharString
    # - Hints affect all subsequent path operations
    #
    # @example Apply hints to a CharString
    #   applier = PostScriptHintApplier.new
    #   charstring_with_hints = applier.apply(charstring, hints)
    class PostScriptHintApplier
      # CFF CharString operators
      HSTEM = 1
      VSTEM = 3
      HINTMASK = 19
      CNTRMASK = 20
      HSTEM3 = [12, 2]
      VSTEM3 = [12, 1]

      # Apply hints to CharString
      #
      # @param charstring [String] Original CharString bytes
      # @param hints [Array<Hint>] Hints to apply
      # @return [String] CharString with applied hints
      def apply(charstring, hints)
        return charstring if hints.nil? || hints.empty?
        return charstring if charstring.nil? || charstring.empty?

        # Build hint operators
        hint_ops = build_hint_operators(hints)

        # Insert hints at the beginning of CharString
        # (simplified - real implementation would analyze existing structure)
        hint_ops + charstring
      end

      private

      # Build hint operators from hints
      #
      # @param hints [Array<Hint>] Hints to convert
      # @return [String] Hint operator bytes
      def build_hint_operators(hints)
        operators = "".b

        # Group hints by type for proper ordering
        stem_hints = hints.select { |h| h.type == :stem }
        stem3_hints = hints.select { |h| h.type == :stem3 }
        mask_hints = hints.select { |h| %i[hint_replacement counter].include?(h.type) }

        # Add stem hints first
        stem_hints.each do |hint|
          operators << encode_stem_hint(hint)
        end

        # Add stem3 hints
        stem3_hints.each do |hint|
          operators << encode_stem3_hint(hint)
        end

        # Add mask hints
        mask_hints.each do |hint|
          operators << encode_mask_hint(hint)
        end

        operators
      end

      # Encode stem hint as CharString bytes
      #
      # @param hint [Hint] Stem hint
      # @return [String] Encoded bytes
      def encode_stem_hint(hint)
        data = hint.to_postscript
        return "".b if data.empty?

        args = data[:args] || []
        operator = data[:operator]

        # Encode arguments as CFF integers
        bytes = args.map { |arg| encode_cff_integer(arg) }.join

        # Add operator
        bytes << if operator == :vstem
                   [VSTEM].pack("C")
                 else
                   [HSTEM].pack("C")
                 end

        bytes
      end

      # Encode stem3 hint as CharString bytes
      #
      # @param hint [Hint] Stem3 hint
      # @return [String] Encoded bytes
      def encode_stem3_hint(hint)
        data = hint.to_postscript
        return "".b if data.empty?

        args = data[:args] || []
        operator = data[:operator]

        # Encode arguments
        bytes = args.map { |arg| encode_cff_integer(arg) }.join

        # Add two-byte operator (12 followed by subop)
        bytes << if operator == :vstem3
                   VSTEM3.pack("C*")
                 else
                   HSTEM3.pack("C*")
                 end

        bytes
      end

      # Encode mask hint as CharString bytes
      #
      # @param hint [Hint] Mask hint
      # @return [String] Encoded bytes
      def encode_mask_hint(hint)
        operator = hint.type == :hint_replacement ? HINTMASK : CNTRMASK
        mask = hint.data[:mask] || []

        # Encode mask bytes
        bytes = mask.map { |b| [b].pack("C") }.join

        # Add operator
        bytes + [operator].pack("C")
      end

      # Encode integer as CFF CharString number
      #
      # @param num [Integer] Number to encode
      # @return [String] Encoded bytes
      def encode_cff_integer(num)
        # Range 1: -107 to 107 (single byte)
        if num >= -107 && num <= 107
          return [32 + num].pack("c")
        end

        # Range 2: 108 to 1131 (two bytes)
        if num >= 108 && num <= 1131
          b0 = 247 + ((num - 108) >> 8)
          b1 = (num - 108) & 0xff
          return [b0, b1].pack("C*")
        end

        # Range 3: -1131 to -108 (two bytes)
        if num >= -1131 && num <= -108
          b0 = 251 - ((num + 108) >> 8)
          b1 = -(num + 108) & 0xff
          return [b0, b1].pack("C*")
        end

        # Range 4: -32768 to 32767 (three bytes)
        if num >= -32_768 && num <= 32_767
          bytes = [28, (num >> 8) & 0xff, num & 0xff]
          return bytes.pack("C*")
        end

        # Range 5: Larger numbers (five bytes)
        bytes = [
          255,
          (num >> 24) & 0xff,
          (num >> 16) & 0xff,
          (num >> 8) & 0xff,
          num & 0xff
        ]
        bytes.pack("C*")
      end
    end
  end
end