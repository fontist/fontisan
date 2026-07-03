# frozen_string_literal: true

# Namespace hub for Unicode metadata used by font tooling.
#
# Plane/Block/Script metadata is a separate concern from font format
# parsing — it is pure Unicode knowledge. Keeping it under its own
# namespace (rather than scattering it across +Tables+ or +Stitcher+)
# keeps the data MECE: one concept, one home.
#
# Each metadata concept (Plane, Block, Script) lives in its own file so
# that adding a new concept is additive (open/closed).

module Fontisan
  module Unicode
    autoload :Plane, "fontisan/unicode/plane"
  end
end
