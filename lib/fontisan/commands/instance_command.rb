# frozen_string_literal: true

require "thor"
require_relative "base_command"
require_relative "../variation/instance_generator"
require_relative "../variation/instance_writer"
require_relative "../variation/validator"
require_relative "../error"

module Fontisan
  module Commands
    # CLI command for generating static font instances from variable fonts
    #
    # Provides command-line interface for:
    # - Instancing at specific coordinates
    # - Using named instances
    # - Converting output format during instancing
    # - Listing available instances
    # - Validation before generation
    # - Dry-run mode for previewing
    # - Progress tracking
    #
    # @example Instance at coordinates
    #   fontisan instance variable.ttf --wght=700 --output=bold.ttf
    #
    # @example Instance with format conversion
    #   fontisan instance variable.ttf --wght=700 --to=otf --output=bold.otf
    #
    # @example Instance with validation
    #   fontisan instance variable.ttf --wght=700 --validate --output=bold.ttf
    #
    # @example Dry-run to preview
    #   fontisan instance variable.ttf --wght=700 --dry-run
    class InstanceCommand < BaseCommand
      # Instance a variable font at specified coordinates
      #
      # @param input_path [String] Path to variable font file
      def execute(input_path, options = {})
        # Load variable font
        font = load_font(input_path)

        # Validate font if requested
        validate_font(font) if options[:validate]

        # Handle list-instances option
        if options[:list_instances]
          list_instances(font)
          return
        end

        # Handle dry-run mode
        if options[:dry_run]
          preview_instance(font, input_path, options)
          return
        end

        # Determine output path
        output_path = determine_output_path(input_path, options)

        # Generate instance
        if options[:named_instance]
          instance_named(font, options[:named_instance], output_path, options)
        else
          instance_coords(font, extract_coordinates(options), output_path,
                          options)
        end

        puts "Static font instance written to: #{output_path}"
      rescue VariationError => e
        warn "Variation Error: #{e.detailed_message}"
        exit 1
      rescue StandardError => e
        warn "Error: #{e.message}"
        warn e.backtrace.first(5).join("\n") if options[:verbose]
        exit 1
      end

      private

      # Validate font before generating instance
      #
      # @param font [Object] Font object
      def validate_font(font)
        puts "Validating font..." if @options[:verbose]

        validator = Variation::Validator.new(font)
        errors = validator.validate

        if errors.any?
          warn "Validation errors found:"
          errors.each do |error|
            warn "  - #{error}"
          end
          exit 1
        end

        puts "Font validation passed" if @options[:verbose]
      end

      # Preview instance without generating
      #
      # @param font [Object] Font object
      # @param input_path [String] Input file path
      # @param options [Hash] Command options
      def preview_instance(_font, input_path, options)
        coords = extract_coordinates(options)

        if coords.empty?
          raise ArgumentError,
                "No coordinates specified. Use --wght=700, --wdth=100, etc."
        end

        puts "Dry-run mode: Preview of instance generation"
        puts
        puts "Coordinates:"
        coords.each do |axis, value|
          puts "  #{axis}: #{value}"
        end
        puts
        puts "Output would be written to: #{determine_output_path(input_path,
                                                                  options)}"
        puts "Output format: #{options[:to] || 'same as input'}"
        puts
        puts "Use without --dry-run to actually generate the instance."
      end

      # Instance at specific coordinates
      #
      # @param font [Object] Font object
      # @param coords [Hash] User coordinates
      # @param output_path [String] Output file path
      # @param options [Hash] Command options
      def instance_coords(font, coords, output_path, options)
        if coords.empty?
          raise ArgumentError,
                "No coordinates specified. Use --wght=700, --wdth=100, etc."
        end

        # Show progress if requested
        print "Generating instance..." if options[:progress]

        # Generate instance tables using InstanceGenerator
        generator = Variation::InstanceGenerator.new(font, coords)
        tables = generator.generate

        puts " done" if options[:progress]

        # Write instance using InstanceWriter
        print "Writing output..." if options[:progress]

        # Detect source format for conversion
        source_format = detect_source_format(font)

        Variation::InstanceWriter.write(
          tables,
          output_path,
          format: options[:to]&.to_sym,
          source_format: source_format,
          optimize: options[:optimize] || false,
        )

        puts " done" if options[:progress]
      end

      # Instance using named instance
      #
      # @param font [Object] Font object
      # @param instance_index [Integer] Named instance index
      # @param output_path [String] Output file path
      # @param options [Hash] Command options
      def instance_named(font, instance_index, output_path, options)
        # Generate instance using named instance
        generator = Variation::InstanceGenerator.new(font)
        tables = generator.generate_named_instance(instance_index)

        # Detect source format
        source_format = detect_source_format(font)

        # Write instance
        Variation::InstanceWriter.write(
          tables,
          output_path,
          format: options[:to]&.to_sym,
          source_format: source_format,
          optimize: options[:optimize] || false,
        )
      end

      # List available named instances
      #
      # @param font [Object] Font object
      def list_instances(font)
        fvar = font.table("fvar")
        unless fvar
          puts "Not a variable font - no named instances available."
          return
        end

        instances = fvar.instances
        if instances.empty?
          puts "No named instances defined in font."
          return
        end

        puts "Available named instances:"
        puts

        instances.each_with_index do |instance, index|
          name_id = instance[:subfamily_name_id]
          puts "  [#{index}] Instance #{name_id}"
          puts "    Coordinates:"
          instance[:coordinates].each_with_index do |value, axis_index|
            next if axis_index >= fvar.axes.length

            axis = fvar.axes[axis_index]
            puts "      #{axis.axis_tag}: #{value}"
          end
          puts
        end
      end

      # Extract axis coordinates from options
      #
      # @param options [Hash] Command options
      # @return [Hash] Coordinates hash
      def extract_coordinates(options)
        coords = {}

        # Check for common axis options
        coords["wght"] = options[:wght].to_f if options[:wght]
        coords["wdth"] = options[:wdth].to_f if options[:wdth]
        coords["slnt"] = options[:slnt].to_f if options[:slnt]
        coords["ital"] = options[:ital].to_f if options[:ital]
        coords["opsz"] = options[:opsz].to_f if options[:opsz]

        # Allow arbitrary axis coordinates via --axis-TAG=value
        options.each do |key, value|
          key_str = key.to_s
          if key_str.start_with?("axis_")
            axis_tag = key_str.sub("axis_", "")
            coords[axis_tag] = value.to_f
          end
        end

        coords
      end

      # Determine output path
      #
      # @param input_path [String] Input file path
      # @param options [Hash] Command options
      # @return [String] Output path
      def determine_output_path(input_path, options)
        return options[:output] if options[:output]

        # Generate default output name
        base = File.basename(input_path, ".*")
        ext = options[:to] || File.extname(input_path)[1..]
        dir = File.dirname(input_path)

        "#{dir}/#{base}-instance.#{ext}"
      end

      # Detect source format from font
      #
      # @param font [Object] Font object
      # @return [Symbol] Source format (:ttf or :otf)
      def detect_source_format(font)
        font.has_table?("CFF ") || font.has_table?("CFF2") ? :otf : :ttf
      end

      # Load font from file
      #
      # @param path [String] Font file path
      # @return [Object] Font object
      def load_font(path)
        unless File.exist?(path)
          raise ArgumentError, "Font file not found: #{path}"
        end

        FontLoader.load(path)
      rescue StandardError => e
        raise ArgumentError, "Failed to load font: #{e.message}"
      end
    end
  end
end
