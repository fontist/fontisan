# frozen_string_literal: true

module Fontisan
  module Subset
    # Glyph ID mapping management
    #
    # This class manages the mapping between original glyph IDs (GIDs) in the
    # source font and new GIDs in the subset font. It supports two modes:
    #
    # 1. Compact mode (retain_gids: false): Glyphs are renumbered sequentially,
    #    eliminating gaps from removed glyphs. This produces smaller fonts.
    #
    # 2. Retain mode (retain_gids: true): Original glyph IDs are preserved,
    #    with removed glyphs leaving empty slots. This maintains glyph
    #    references but produces larger fonts.
    #
    # @example Compact mode (default)
    #   mapping = Fontisan::Subset::GlyphMapping.new([0, 5, 10, 15])
    #   mapping.new_id(5)  # => 1
    #   mapping.new_id(10) # => 2
    #   mapping.size       # => 4
    #
    # @example Retain mode
    #   mapping = Fontisan::Subset::GlyphMapping.new([0, 5, 10, 15], retain_gids: true)
    #   mapping.new_id(5)  # => 5
    #   mapping.new_id(10) # => 10
    #   mapping.size       # => 16 (0..15)
    #
    # @example Reverse lookup
    #   mapping = Fontisan::Subset::GlyphMapping.new([0, 5, 10])
    #   mapping.old_id(1) # => 5
    class GlyphMapping
      include Enumerable

      # @return [Hash<Integer, Integer>] mapping from old GIDs to new GIDs
      attr_reader :old_to_new

      # @return [Hash<Integer, Integer>] mapping from new GIDs to old GIDs
      attr_reader :new_to_old

      # @return [Boolean] whether original GIDs are retained
      attr_reader :retain_gids

      # Initialize glyph mapping
      #
      # @param old_glyph_ids [Array<Integer>] array of glyph IDs to include
      #   in the subset, typically sorted
      # @param retain_gids [Boolean] whether to preserve original glyph IDs
      #
      # @example Create compact mapping
      #   mapping = GlyphMapping.new([0, 3, 5, 10])
      #
      # @example Create mapping that retains GIDs
      #   mapping = GlyphMapping.new([0, 3, 5, 10], retain_gids: true)
      def initialize(old_glyph_ids, retain_gids: false)
        @old_to_new = {}
        @new_to_old = {}
        @retain_gids = retain_gids

        build_mappings(old_glyph_ids)
      end

      # Get new glyph ID for an old glyph ID
      #
      # @param old_id [Integer] original glyph ID
      # @return [Integer, nil] new glyph ID, or nil if not in subset
      #
      # @example
      #   mapping = GlyphMapping.new([0, 5, 10])
      #   mapping.new_id(5)  # => 1
      #   mapping.new_id(99) # => nil
      def new_id(old_id)
        old_to_new[old_id]
      end

      # Get old glyph ID for a new glyph ID
      #
      # @param new_id [Integer] new glyph ID in subset
      # @return [Integer, nil] original glyph ID, or nil if invalid
      #
      # @example
      #   mapping = GlyphMapping.new([0, 5, 10])
      #   mapping.old_id(1) # => 5
      #   mapping.old_id(99) # => nil
      def old_id(new_id)
        new_to_old[new_id]
      end

      # Get number of glyphs in the subset
      #
      # In compact mode, this is the number of included glyphs.
      # In retain mode, this is the highest old GID + 1.
      #
      # @return [Integer] number of glyphs
      #
      # @example Compact mode
      #   mapping = GlyphMapping.new([0, 5, 10])
      #   mapping.size # => 3
      #
      # @example Retain mode
      #   mapping = GlyphMapping.new([0, 5, 10], retain_gids: true)
      #   mapping.size # => 11 (0..10)
      def size
        new_to_old.size
      end

      # Check if a glyph is included in the subset
      #
      # @param old_id [Integer] original glyph ID to check
      # @return [Boolean] true if glyph is in subset
      #
      # @example
      #   mapping = GlyphMapping.new([0, 5, 10])
      #   mapping.include?(5)  # => true
      #   mapping.include?(99) # => false
      def include?(old_id)
        old_to_new.key?(old_id)
      end

      # Get array of all old glyph IDs in subset
      #
      # @return [Array<Integer>] sorted array of old glyph IDs
      #
      # @example
      #   mapping = GlyphMapping.new([10, 0, 5])
      #   mapping.old_ids # => [0, 5, 10]
      def old_ids
        old_to_new.keys.sort
      end

      # Get array of all new glyph IDs in subset
      #
      # @return [Array<Integer>] sorted array of new glyph IDs
      #
      # @example
      #   mapping = GlyphMapping.new([0, 5, 10])
      #   mapping.new_ids # => [0, 1, 2]
      def new_ids
        new_to_old.keys.sort
      end

      # Iterate over all glyph mappings
      #
      # Yields old_id and new_id pairs in order of old glyph IDs.
      #
      # @yield [old_id, new_id] each glyph mapping
      # @yieldparam old_id [Integer] original glyph ID
      # @yieldparam new_id [Integer] new glyph ID
      #
      # @example
      #   mapping = GlyphMapping.new([0, 5, 10])
      #   mapping.each do |old_id, new_id|
      #     puts "#{old_id} => #{new_id}"
      #   end
      #   # Output:
      #   # 0 => 0
      #   # 5 => 1
      #   # 10 => 2
      def each
        return enum_for(:each) unless block_given?

        old_ids.each do |old_id|
          yield old_id, old_to_new[old_id]
        end
      end

      private

      # Build the bidirectional mapping tables
      #
      # @param old_glyph_ids [Array<Integer>] glyph IDs to map
      def build_mappings(old_glyph_ids)
        if retain_gids
          build_retained_mappings(old_glyph_ids)
        else
          build_compact_mappings(old_glyph_ids)
        end
      end

      # Build mappings in compact mode
      #
      # Assigns sequential new GIDs starting from 0, preserving the order
      # of old GIDs.
      #
      # @param old_glyph_ids [Array<Integer>] glyph IDs to map
      def build_compact_mappings(old_glyph_ids)
        sorted_ids = old_glyph_ids.sort.uniq
        sorted_ids.each_with_index do |old_id, new_id|
          old_to_new[old_id] = new_id
          new_to_old[new_id] = old_id
        end
      end

      # Build mappings in retain GID mode
      #
      # Preserves original GIDs, creating empty slots for removed glyphs.
      #
      # @param old_glyph_ids [Array<Integer>] glyph IDs to map
      def build_retained_mappings(old_glyph_ids)
        sorted_ids = old_glyph_ids.sort.uniq
        max_id = sorted_ids.max || 0

        # Map each glyph to itself
        sorted_ids.each do |old_id|
          old_to_new[old_id] = old_id
          new_to_old[old_id] = old_id
        end

        # Fill in empty slots for removed glyphs with nil mappings
        # This ensures size calculation includes the empty slots
        (0..max_id).each do |gid|
          new_to_old[gid] ||= nil
        end
      end
    end
  end
end
