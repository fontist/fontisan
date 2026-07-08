# frozen_string_literal: true

# Per-survivor placement: where the source bitmap lives and where it
# ends up in the subset CBDT.
module Fontisan
  module Subset
    module TableStrategy
      ColorBitmapPlacement = Struct.new(:source_gid, :new_gid,
                                        :source_offset, :byte_length,
                                        :image_format, :strike_ppem,
                                        :new_offset,
                                        keyword_init: true) do
        def initialize(*)
          super
          self.new_offset ||= 0
        end
      end
    end
  end
end
