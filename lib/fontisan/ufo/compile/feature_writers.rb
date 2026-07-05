# frozen_string_literal: true

module Fontisan
  module Ufo
    module Compile
      # Feature writers extract GSUB/GPOS feature data from a UFO
      # source. Each writer is a class extending {FeatureWriters::Base}
      # with a +#write+ method that returns a {FeatureOutput} value
      # object (or +nil+ if the UFO has no data for that feature).
      #
      # The compiler runs registered writers, collects their outputs,
      # and feeds each into the corresponding table builder
      # (`Tables::Gpos`, `Tables::Gsub`, etc.) for binary encoding.
      #
      # OCP: adding a new feature writer = new class + one REGISTRY
      # entry. No edits to the compiler.
      module FeatureWriters
        autoload :Base, "fontisan/ufo/compile/feature_writers/base"
        autoload :Kern, "fontisan/ufo/compile/feature_writers/kern"
        autoload :Gdef, "fontisan/ufo/compile/feature_writers/gdef"
        autoload :Mark, "fontisan/ufo/compile/feature_writers/mark"

        # Default writer set — what the compiler runs when the user
        # doesn't override. Per feature, +#write+ returns +nil+ when
        # the UFO has no data for that feature, so it's safe to
        # always run them all.
        DEFAULT_WRITERS = [Gdef, Kern, Mark].freeze
      end
    end
  end
end
