# frozen_string_literal: true

require "yaml"

module Fontisan
  module Subset
    # Subsetting profiles
    #
    # This class manages font subsetting profiles that specify which
    # font tables should be included in the subset. Profiles are loaded from
    # an external YAML configuration file for flexibility and maintainability.
    #
    # @example Get tables for PDF profile
    #   tables = Fontisan::Subset::Profile.for_name("pdf")
    #   # => ["cmap", "head", "hhea", "hmtx", "maxp", "name", "post", "loca", "glyf"]
    #
    # @example Get tables for web profile
    #   tables = Fontisan::Subset::Profile.for_name("web")
    #   # => ["cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "loca", "glyf"]
    #
    # @example Create custom profile
    #   tables = Fontisan::Subset::Profile.custom(["cmap", "head", "hhea"])
    #   # => ["cmap", "head", "hhea"]
    class Profile
      # All known font table tags
      #
      # Comprehensive list of all standard TrueType/OpenType tables
      KNOWN_TABLES = %w[
        cmap head hhea hmtx maxp name OS/2 post
        loca glyf cvt fpgm prep gasp
        GSUB GPOS GDEF BASE JSTF
        CFF CFF2 VORG
        EBDT EBLC EBSC
        CBDT CBLC sbix
        kern vhea vmtx
        LTSH PCLT VDMX hdmx
        fvar gvar avar cvar HVAR VVAR MVAR STAT
        DSIG
      ].freeze

      class << self
        # Get table list for a named profile
        #
        # @param name [String] profile name (pdf, web, minimal, full)
        # @raise [ArgumentError] if profile name is unknown
        # @return [Array<String>] array of table tags
        #
        # @example
        #   Profile.for_name("pdf")
        #   # => ["cmap", "head", "hhea", "hmtx", "maxp", "name", "post", "loca", "glyf"]
        def for_name(name)
          profiles = load_profiles
          profile_config = profiles[name.to_s.downcase]

          unless profile_config
            raise ArgumentError,
                  "Unknown profile '#{name}'. Valid profiles: #{valid_names.join(', ')}"
          end

          profile_config["tables"].dup
        end

        # Create a custom profile with specified tables
        #
        # Validates that all provided table tags are recognized and returns
        # the list of tables in a consistent format.
        #
        # @param tables [Array<String>] array of table tags
        # @raise [ArgumentError] if any table tag is unknown
        # @return [Array<String>] validated array of table tags
        #
        # @example Create custom profile
        #   Profile.custom(["cmap", "head", "glyf"])
        #   # => ["cmap", "head", "glyf"]
        #
        # @example Invalid table raises error
        #   Profile.custom(["cmap", "invalid"])
        #   # => ArgumentError: Unknown table tags: invalid
        def custom(tables)
          tables = Array(tables)
          unknown = tables - KNOWN_TABLES

          unless unknown.empty?
            raise ArgumentError,
                  "Unknown table tags: #{unknown.join(', ')}"
          end

          tables.dup
        end

        # Check if a table tag is recognized
        #
        # @param table [String] table tag to check
        # @return [Boolean] true if table is known
        #
        # @example
        #   Profile.known_table?("cmap") # => true
        #   Profile.known_table?("invalid") # => false
        def known_table?(table)
          KNOWN_TABLES.include?(table.to_s)
        end

        # Get list of all valid profile names
        #
        # @return [Array<String>] array of profile names
        #
        # @example
        #   Profile.valid_names # => ["pdf", "web", "minimal", "full"]
        def valid_names
          load_profiles.keys.sort
        end

        # Get profile description
        #
        # @param name [String] profile name
        # @return [String, nil] profile description or nil if not found
        #
        # @example
        #   Profile.description("pdf")
        #   # => "Minimal tables required for PDF font embedding"
        def description(name)
          profiles = load_profiles
          profile_config = profiles[name.to_s.downcase]
          profile_config&.dig("description")
        end

        private

        # Load profiles from YAML configuration file
        #
        # @return [Hash] Hash of profile configurations
        def load_profiles
          @load_profiles ||= begin
            config_path = File.join(__dir__, "../config/subset_profiles.yml")
            YAML.load_file(config_path)
          rescue Errno::ENOENT
            raise Fontisan::Error,
                  "Profile configuration file not found: #{config_path}"
          rescue Psych::SyntaxError => e
            raise Fontisan::Error,
                  "Invalid YAML in profile configuration: #{e.message}"
          end
        end

        # Clear cached profiles (useful for testing)
        def clear_cache!
          @load_profiles = nil
        end
      end
    end
  end
end
