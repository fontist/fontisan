# frozen_string_literal: true

module Fontisan
  module Subset
    # Value object handed to every TableStrategy. Encapsulates the inputs
    # (font, mapping, options) plus the cross-strategy [SharedState] so
    # strategies don't need a back-reference to the TableSubsetter.
    #
    # @!attribute font
    #   @return [SfntFont]
    # @!attribute mapping
    #   @return [GlyphMapping]
    # @!attribute options
    #   @return [Options]
    # @!attribute state
    #   @return [SharedState]
    SubsetContext = Struct.new(:font, :mapping, :options, :state,
                               keyword_init: true)
  end
end
