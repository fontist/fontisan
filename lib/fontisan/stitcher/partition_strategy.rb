# frozen_string_literal: true

module Fontisan
  class Stitcher
    # Namespace for codepoint partitioners that split a codepoint set
    # across named subfonts while respecting the format's glyph cap.
    #
    # A partitioner is a strategy object with a single entry point
    # (`.partition`) that takes a +{codepoint => donor}+ map and returns
    # a {Blueprint}. The blueprint is then applied to a Stitcher via
    # {Blueprint#apply_to}.
    #
    # Adding a new partitioner = adding a new file + a new entry here.
    # No edits to existing partitioners required (open/closed).
    module PartitionStrategy
      autoload :Base, "fontisan/stitcher/partition_strategy/base"
      autoload :Blueprint, "fontisan/stitcher/partition_strategy/blueprint"
      autoload :Partition, "fontisan/stitcher/partition_strategy/partition"
      autoload :ByPlane, "fontisan/stitcher/partition_strategy/by_plane"
    end
  end
end
