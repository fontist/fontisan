# frozen_string_literal: true

module Fontisan
  class Error < StandardError; end

  class InvalidFontError < Error; end

  class UnsupportedFormatError < Error; end

  class CorruptedTableError < Error; end

  class MissingTableError < Error; end

  class ParseError < Error; end

  class SubsettingError < Error; end

  # Base variation error with context and suggestions
  #
  # Provides detailed error information including context hash and
  # actionable suggestions for resolution.
  class VariationError < Error
    # @return [Hash] Error context (axis, value, range, etc.)
    attr_reader :context

    # @return [String, nil] Suggested fix
    attr_reader :suggestion

    # Initialize variation error
    #
    # @param message [String] Error message
    # @param context [Hash] Error context
    # @param suggestion [String, nil] Suggested fix
    def initialize(message, context: {}, suggestion: nil)
      super(message)
      @context = context
      @suggestion = suggestion
    end

    # Get detailed error message with context and suggestion
    #
    # @return [String] Formatted error message
    def detailed_message
      msg = message
      msg += "\nContext: #{@context.inspect}" if @context.any?
      msg += "\nSuggestion: #{@suggestion}" if @suggestion
      msg
    end
  end

  # Invalid coordinate value for variation axis
  #
  # Raised when coordinate is outside valid axis range.
  class InvalidCoordinatesError < VariationError
    # Initialize with axis details
    #
    # @param axis [String] Axis tag
    # @param value [Float] Invalid value
    # @param range [Range, Array] Valid range
    # @param message [String, nil] Custom message
    def initialize(axis: nil, value: nil, range: nil, message: nil)
      if message
        super(message, context: { axis: axis, value: value, range: range })
      else
        min_val = range.is_a?(Range) ? range.min : range.first
        max_val = range.is_a?(Range) ? range.max : range.last

        super(
          "Invalid coordinate for axis '#{axis}': #{value}",
          context: { axis: axis, value: value, range: range },
          suggestion: "Use value between #{min_val} and #{max_val}"
        )
      end
    end
  end

  # Missing required variation table
  #
  # Raised when font lacks required variation tables.
  class MissingVariationTableError < VariationError
    # Initialize with table tag
    #
    # @param table [String] Missing table tag
    # @param message [String, nil] Custom message
    def initialize(table: nil, message: nil)
      if message
        super(message, context: { table: table })
      else
        super(
          "Missing required variation table: #{table}",
          context: { table: table },
          suggestion: "This font is not a variable font or lacks #{table} table"
        )
      end
    end
  end

  # Invalid variation axis specification
  #
  # Raised when axis definition is malformed or invalid.
  class InvalidAxisError < VariationError
    # Initialize with axis details
    #
    # @param axis [String] Axis tag
    # @param reason [String] Why axis is invalid
    def initialize(axis:, reason:)
      super(
        "Invalid variation axis '#{axis}': #{reason}",
        context: { axis: axis, reason: reason },
        suggestion: "Check axis definition in fvar table"
      )
    end
  end

  # Overlapping variation regions detected
  #
  # Raised when variation regions overlap improperly.
  class RegionOverlapError < VariationError
    # Initialize with region details
    #
    # @param region1 [Integer] First region index
    # @param region2 [Integer] Second region index
    def initialize(region1:, region2:)
      super(
        "Overlapping variation regions: #{region1} and #{region2}",
        context: { region1: region1, region2: region2 },
        suggestion: "Check variation region definitions for conflicts"
      )
    end
  end

  # Delta count mismatch
  #
  # Raised when delta arrays have mismatched lengths.
  class DeltaMismatchError < VariationError
    # Initialize with delta details
    #
    # @param expected [Integer] Expected delta count
    # @param actual [Integer] Actual delta count
    # @param location [String] Where mismatch occurred
    def initialize(expected:, actual:, location:)
      super(
        "Delta count mismatch at #{location}: expected #{expected}, got #{actual}",
        context: { expected: expected, actual: actual, location: location },
        suggestion: "Verify variation data integrity in #{location}"
      )
    end
  end

  # Invalid instance index
  #
  # Raised when named instance index is out of range.
  class InvalidInstanceIndexError < VariationError
    # Initialize with instance details
    #
    # @param index [Integer] Requested index
    # @param max [Integer] Maximum valid index
    def initialize(index:, max:)
      super(
        "Invalid instance index: #{index} (max: #{max})",
        context: { index: index, max: max },
        suggestion: "Use index between 0 and #{max}"
      )
    end
  end

  # Variation data corruption
  #
  # Raised when variation data appears corrupted or invalid.
  class CorruptedVariationDataError < VariationError
    # Initialize with corruption details
    #
    # @param table [String] Table with corrupted data
    # @param details [String] Corruption details
    def initialize(table:, details:)
      super(
        "Corrupted variation data in #{table}: #{details}",
        context: { table: table, details: details },
        suggestion: "Font file may be damaged, try re-downloading or using original"
      )
    end
  end

  # Invalid variation data
  #
  # Raised when variation data is invalid but not necessarily corrupted.
  # Used for validation failures.
  class InvalidVariationDataError < VariationError
    # Initialize with validation details
    #
    # @param message [String] Error message
    # @param details [Hash] Error details
    def initialize(message:, details: {})
      super(
        message,
        context: details,
        suggestion: "Check font variation data and structure"
      )
    end
  end

  # Variation data corrupted (for use in data_extractor)
  #
  # Raised when extracted variation data appears corrupted.
  class VariationDataCorruptedError < VariationError
    # Initialize with corruption details
    #
    # @param message [String] Error message
    # @param details [Hash] Corruption details
    def initialize(message:, details: {})
      super(
        message,
        context: details,
        suggestion: "Font variation data may be corrupted"
      )
    end
  end
end
