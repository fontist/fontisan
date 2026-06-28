# frozen_string_literal: true

module Fontisan
  module FontBuilder
    NameRecord = Struct.new(
      :name_id, :platform_id, :encoding_id, :language_id, :string,
      keyword_init: true
    ) do
      WINDOWS_UNICODE_PLATFORM = 3
      WINDOWS_UNICODE_BMP_ENCODING = 1
      ENGLISH_US = 0x0409

      def initialize(
        name_id:,
        string:,
        platform_id: WINDOWS_UNICODE_PLATFORM,
        encoding_id: WINDOWS_UNICODE_BMP_ENCODING,
        language_id: ENGLISH_US
      )
        super
      end
    end
  end
end
