# frozen_string_literal: true

module Fontisan
  module Tables
    # Single source of truth mapping OpenType table tags to Ruby classes.
    #
    # Each table class registers itself via `register_tag`:
    #
    #   module Fontisan::Tables
    #     class Hvar < Binary::BaseRecord
    #       register_tag "HVAR"
    #       ...
    #     end
    #   end
    #
    # Dispatch sites use `Tables::Registry.for(tag)` instead of a
    # `case tag when "HVAR"` switch. This is OCP-compliant: adding a
    # new table means adding one `register_tag` line in the table's
    # file, not editing every dispatch site.
    module Registry
      @by_tag = {}
      @by_class = {}

      class << self
        # @api internal Called by table classes at load time.
        # @param tag [String] Four-byte OpenType table tag (e.g., "HVAR").
        # @param klass [Class] The Ruby class implementing the table.
        def register(tag, klass)
          @by_tag[tag] = klass
          @by_class[klass] = tag
        end

        # Look up the table class for a tag.
        #
        # @param tag [String] Four-byte OpenType table tag.
        # @return [Class, nil] The table class, or nil if unknown.
        def for(tag)
          @by_tag[tag]
        end

        # Reverse lookup: tag for a given class.
        #
        # @param klass [Class] A table class.
        # @return [String, nil] The tag, or nil if not registered.
        def tag_for(klass)
          @by_class[klass]
        end

        # @return [Array<String>] All registered tags.
        def tags
          @by_tag.keys
        end

        # Clear all registrations (testing only).
        def __clear__
          @by_tag.clear
          @by_class.clear
        end
      end
    end

    # Mixin applied to table classes that register themselves with the
    # Registry at load time. Used via `register_tag "HVAR"` in the
    # class body.
    module Registered
      def register_tag(tag)
        Tables::Registry.register(tag, self)
      end
    end
  end
end
