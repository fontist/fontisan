# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    FakeAxis = Struct.new(:axis_tag, :min_value, :default_value, :max_value,
                          keyword_init: true)
  end
end
