# frozen_string_literal: true

require "thor"
require_relative "base_command"
require_relative "../variable/instancer"
require_relative "../converters/format_converter"

module Fontisan
  module Commands
    # CLI command for generating static font instances from variable fonts
    #
    # Provides command-line interface for:
    # - Instancing at specific coordinates
    # - Using named instances
    # - Converting output format during instancing
    # - Listing available instances
    #
    # @example Instance at coordinates
    #   fontisan instance variable.ttf --wght=700 --output=bold.ttf
    #
    # @example Instance using named instance
    #   fontisan instance variable.ttf --named-instance="Bold" --output=bold.ttf
    #
    # @example Instance with format conversion
    #   fontisan instance variable.ttf --wght=700 --to=woff2 --output=bold.woff2
    class InstanceCommand < BaseCommand
      # Instance a variable font at specified coordinates
      #
      # @param input_path [String] Path to variable font file
      def execute(input_path, options = {})
        # Load variable font
        font = load_font(input_path)

        # Create instancer
        instancer = Variable::Instancer.new(font)

        # Handle list-instances option
        if options[:list_instances]
          list_instances(instancer)
          return
        end

        # Determine output path
        output_path = determine_output_path(input_path, options)

        # Generate instance
        if options[:named_instance]
          instance_named(instancer, options[:named_instance], output_path,
                         options)
        else
          instance_coords(instancer, extract_coordinates(options), output_path,
                          options)
        end

        puts "Static font instance written to: #{output_path}"
      end

      private

      # Instance at specific coordinates
      #
      # @param instancer [Variable::Instancer] Instancer object
      # @param coords [Hash] User coordinates
      # @param output_path [String] Output file path
      # @param options [Hash] Command options
      def instance_coords(instancer, coords, output_path, options)
        if coords.empty?
          raise ArgumentError,
                "No coordinates specified. Use --wght=700, --wdth=100, etc."
        end

        # Generate instance
        binary = instancer.instance(coords)

        # Convert format if requested
        binary = convert_format(binary, options) if options[:to]

        # Write to file
        File.binwrite(output_path, binary)
      end

      # Instance using named instance
      #
      # @param instancer [Variable::Instancer] Instancer object
      # @param instance_name [String] Named instance name
      # @param output_path [String] Output file path
      # @param options [Hash] Command options
      def instance_named(instancer, instance_name, output_path, options)
        # Generate instance
        binary = instancer.instance_named(instance_name)

        # Convert format if requested
        binary = convert_format(binary, options) if options[:to]

        # Write to file
        File.binwrite(output_path, binary)
      end

      # List available named instances
      #
      # @param instancer [Variable::Instancer] Instancer object
      def list_instances(instancer)
        instances = instancer.named_instances

        if instances.empty?
          puts "No named instances defined in font."
          return
        end

        puts "Available named instances:"
        puts

        instances.each do |instance|
          puts "  #{instance[:name]}"
          puts "    Coordinates:"
          instance[:coordinates].each do |axis, value|
            puts "      #{axis}: #{value}"
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

      # Convert format using FormatConverter
      #
      # @param binary [String] Font binary
      # @param options [Hash] Command options
      # @return [String] Converted binary
      def convert_format(binary, options)
        target_format = options[:to].to_sym

        # Load font from binary
        require "tempfile"
        Tempfile.create(["instance", ".ttf"]) do |temp_file|
          temp_file.binmode
          temp_file.write(binary)
          temp_file.flush

          font = FontLoader.load(temp_file.path)
          converter = Converters::FormatConverter.new

          result = converter.convert(font, target_format)

          case target_format
          when :woff, :woff2
            result[:font_data]
          when :svg
            result[:svg_xml]
          else
            binary
          end
        end
      rescue StandardError => e
        warn "Format conversion failed: #{e.message}"
        binary
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
