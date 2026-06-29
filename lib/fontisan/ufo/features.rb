# frozen_string_literal: true

module Fontisan
  module Ufo
    # Wrapper around the FEA feature source in `features.fea`.
    #
    # The MVP just stores the raw text. A FEA parser/compiler lands in
    # TODO 08 (feature writers).
    class Features
      attr_accessor :text

      def initialize(text: "")
        @text = text
      end
    end
  end
end
