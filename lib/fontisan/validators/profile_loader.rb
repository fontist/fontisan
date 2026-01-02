# frozen_string_literal: true

require_relative "basic_validator"
require_relative "font_book_validator"
require_relative "opentype_validator"
require_relative "web_font_validator"

module Fontisan
  module Validators
    # ProfileLoader manages validation profiles and loads appropriate validators
    #
    # This class provides a registry of validation profiles, each configured for
    # specific use cases. Profiles define which validator to use, loading mode,
    # and severity thresholds.
    #
    # Available profiles:
    # - indexability: Fast validation for font discovery (BasicValidator)
    # - usability: Basic usability for installation (FontBookValidator)
    # - production: Comprehensive quality checks (OpenTypeValidator)
    # - web: Web embedding and optimization (WebFontValidator)
    # - spec_compliance: Full OpenType spec compliance (OpenTypeValidator)
    # - default: Alias for production profile
    #
    # @example Loading a profile
    #   validator = ProfileLoader.load(:production)
    #   report = validator.validate(font)
    #
    # @example Getting profile info
    #   info = ProfileLoader.profile_info(:web)
    #   puts info[:description]
    class ProfileLoader
      # Profile definitions (hardcoded, no YAML)
      PROFILES = {
        indexability: {
          name: "Font Indexability",
          description: "Fast validation for font discovery and indexing",
          validator: "BasicValidator",
          loading_mode: "metadata",
          severity_threshold: "error",
        },
        usability: {
          name: "Font Usability",
          description: "Basic usability for installation",
          validator: "FontBookValidator",
          loading_mode: "full",
          severity_threshold: "warning",
        },
        production: {
          name: "Production Quality",
          description: "Comprehensive quality checks",
          validator: "OpenTypeValidator",
          loading_mode: "full",
          severity_threshold: "warning",
        },
        web: {
          name: "Web Font Readiness",
          description: "Web embedding and optimization",
          validator: "WebFontValidator",
          loading_mode: "full",
          severity_threshold: "warning",
        },
        spec_compliance: {
          name: "OpenType Specification",
          description: "Full OpenType spec compliance",
          validator: "OpenTypeValidator",
          loading_mode: "full",
          severity_threshold: "info",
        },
        default: {
          name: "Default Profile",
          description: "Default validation profile (alias for production)",
          validator: "OpenTypeValidator",
          loading_mode: "full",
          severity_threshold: "warning",
        },
      }.freeze

      class << self
        # Load a validator for the specified profile
        #
        # @param profile_name [Symbol, String] Profile name
        # @return [Validator] Validator instance for the profile
        # @raise [ArgumentError] if profile name is unknown
        #
        # @example Load production validator
        #   validator = ProfileLoader.load(:production)
        def load(profile_name)
          profile_name = profile_name.to_sym
          profile_config = PROFILES[profile_name]

          unless profile_config
            raise ArgumentError,
                  "Unknown profile: #{profile_name}. " \
                  "Available profiles: #{available_profiles.join(', ')}"
          end

          validator_class_name = profile_config[:validator]
          validator_class = Validators.const_get(validator_class_name)
          validator_class.new
        end

        # Get list of available profile names
        #
        # @return [Array<Symbol>] Array of profile names
        #
        # @example List available profiles
        #   ProfileLoader.available_profiles
        #   # => [:indexability, :usability, :production, :web, :spec_compliance, :default]
        def available_profiles
          PROFILES.keys
        end

        # Get profile configuration
        #
        # @param profile_name [Symbol, String] Profile name
        # @return [Hash, nil] Profile configuration or nil if not found
        #
        # @example Get profile info
        #   info = ProfileLoader.profile_info(:web)
        #   puts info[:description]
        def profile_info(profile_name)
          PROFILES[profile_name.to_sym]
        end

        # Get all profiles with their configurations
        #
        # @return [Hash] All profile configurations
        #
        # @example Get all profiles
        #   ProfileLoader.all_profiles.each do |name, config|
        #     puts "#{name}: #{config[:description]}"
        #   end
        def all_profiles
          PROFILES
        end
      end
    end
  end
end
