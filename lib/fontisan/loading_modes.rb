# frozen_string_literal: true

module Fontisan
  # Loading modes module that defines which tables are loaded in each mode.
  #
  # This module provides a MECE (Mutually Exclusive, Collectively Exhaustive)
  # architecture for font loading modes. Each mode defines a specific set of
  # tables to load, enabling efficient parsing for different use cases.
  #
  # @example Using metadata mode
  #   mode = LoadingModes::METADATA
  #   tables = LoadingModes.tables_for(mode)  # => ["name", "head", "hhea", "maxp", "OS/2", "post"]
  #
  # @example Checking table availability
  #   LoadingModes.table_allowed?(:metadata, "GSUB")  # => false
  #   LoadingModes.table_allowed?(:full, "GSUB")      # => true
  module LoadingModes
    # Metadata mode: loads only tables needed for font identification and metrics
    # Equivalent to otfinfo functionality
    METADATA = :metadata

    # Full mode: loads all tables in the font
    FULL = :full

    # Mode definitions with their respective table lists
    MODES = {
      METADATA => {
        tables: %w[name head hhea maxp OS/2 post].freeze,
        description: "Metadata mode - loads only identification and metrics tables (otfinfo-equivalent)"
      }.freeze,
      FULL => {
        tables: :all,
        description: "Full mode - loads all tables in the font"
      }.freeze
    }.freeze

    # Get the list of tables allowed for a given mode
    #
    # @param mode [Symbol] The loading mode (:metadata or :full)
    # @return [Array<String>, Symbol] Array of table tags or :all for full mode
    # @raise [ArgumentError] if mode is invalid
    def self.tables_for(mode)
      validate_mode!(mode)
      MODES[mode][:tables]
    end

    # Check if a table is allowed in a given mode
    #
    # @param mode [Symbol] The loading mode (:metadata or :full)
    # @param tag [String] The table tag to check
    # @return [Boolean] true if table is allowed in the mode
    # @raise [ArgumentError] if mode is invalid
    def self.table_allowed?(mode, tag)
      validate_mode!(mode)

      tables = MODES[mode][:tables]
      return true if tables == :all

      tables.include?(tag)
    end

    # Validate that a mode is valid
    #
    # @param mode [Symbol] The mode to validate
    # @return [Boolean] true if mode is valid
    def self.valid_mode?(mode)
      MODES.key?(mode)
    end

    # Get the default lazy loading setting for a mode
    #
    # @param mode [Symbol] The loading mode
    # @return [Boolean] true if lazy loading is recommended for this mode
    # @raise [ArgumentError] if mode is invalid
    def self.default_lazy?(mode)
      validate_mode!(mode)
      true  # Lazy loading is recommended for all modes
    end

    # Get mode description
    #
    # @param mode [Symbol] The loading mode
    # @return [String] Description of the mode
    # @raise [ArgumentError] if mode is invalid
    def self.description(mode)
      validate_mode!(mode)
      MODES[mode][:description]
    end

    # Get all available modes
    #
    # @return [Array<Symbol>] List of all mode symbols
    def self.all_modes
      MODES.keys
    end

    # Validate mode and raise error if invalid
    #
    # @param mode [Symbol] The mode to validate
    # @return [void]
    # @raise [ArgumentError] if mode is invalid
    def self.validate_mode!(mode)
      return if valid_mode?(mode)

      raise ArgumentError,
            "Invalid mode: #{mode.inspect}. Valid modes are: #{all_modes.map(&:inspect).join(', ')}"
    end
  end
end
