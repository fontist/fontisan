# frozen_string_literal: true

require "thor"

module Fontisan
  # Command-line interface for Fontisan.
  #
  # This class provides the Thor-based CLI with commands for extracting
  # font information and listing tables. It supports multiple output formats
  # (text, YAML, JSON) and various options for controlling output behavior.
  #
  # @example Run the info command
  #   Fontisan::Cli.start(['info', 'font.ttf'])
  class Cli < Thor
    class_option :format, type: :string, default: "text",
                          desc: "Output format (text, yaml, json)",
                          aliases: "-f"
    class_option :font_index, type: :numeric, default: 0,
                              desc: "Font index for TTC files",
                              aliases: "-i"
    class_option :verbose, type: :boolean, default: false,
                           desc: "Enable verbose output",
                           aliases: "-v"
    class_option :quiet, type: :boolean, default: false,
                         desc: "Suppress non-error output",
                         aliases: "-q"

    desc "info FONT_FILE", "Display font information"
    # Extract and display comprehensive font metadata.
    #
    # @param font_file [String] Path to the font file
    def info(font_file)
      command = Commands::InfoCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "tables FONT_FILE", "List OpenType tables"
    # List all OpenType tables in the font file.
    #
    # @param font_file [String] Path to the font file
    def tables(font_file)
      command = Commands::TablesCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "glyphs FONT_FILE", "List glyph names"
    # List glyph names from the font file.
    #
    # @param font_file [String] Path to the font file
    def glyphs(font_file)
      command = Commands::GlyphsCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "unicode FONT_FILE", "List Unicode to glyph mappings"
    # List Unicode to glyph index mappings from the font file.
    #
    # @param font_file [String] Path to the font file
    def unicode(font_file)
      command = Commands::UnicodeCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "variable FONT_FILE", "Display variable font information"
    # Display variable font variation axes and instances.
    #
    # @param font_file [String] Path to the font file
    def variable(font_file)
      command = Commands::VariableCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "optical-size FONT_FILE", "Display optical size information"
    # Display optical size information from the font file.
    #
    # @param font_file [String] Path to the font file
    def optical_size(font_file)
      command = Commands::OpticalSizeCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "scripts FONT_FILE", "List supported scripts from GSUB/GPOS tables"
    # List all scripts supported by the font from GSUB and GPOS tables.
    #
    # @param font_file [String] Path to the font file
    def scripts(font_file)
      command = Commands::ScriptsCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "features FONT_FILE", "List GSUB/GPOS features"
    option :script, type: :string,
                    desc: "Script tag to query (e.g., latn, cyrl, arab). If not specified, shows features for all scripts",
                    aliases: "-s"
    # List OpenType features available for scripts.
    # If no script is specified, shows features for all scripts.
    #
    # @param font_file [String] Path to the font file
    def features(font_file)
      command = Commands::FeaturesCommand.new(font_file, options)
      result = command.run
      output_result(result)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "dump-table FONT_FILE TABLE_TAG", "Dump raw table data to stdout"
    # Dump raw binary table data to stdout.
    #
    # @param font_file [String] Path to the font file
    # @param table_tag [String] Four-character table tag (e.g., 'name', 'head')
    def dump_table(font_file, table_tag)
      command = Commands::DumpTableCommand.new(font_file, table_tag, options)
      raw_data = command.run

      # Write binary data directly to stdout
      $stdout.binmode
      $stdout.write(raw_data)
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "version", "Display version information"
    # Display the Fontisan version.
    def version
      puts "Fontisan version #{Fontisan::VERSION}"
    end

    private

    # Output the result in the requested format.
    #
    # @param result [Object] The result object to output
    def output_result(result)
      output = case options[:format]
               when "yaml"
                 result.to_yaml
               when "json"
                 result.to_json
               else
                 format_as_text(result)
               end

      puts output unless options[:quiet]
    end

    # Format result as human-readable text.
    #
    # @param result [Object] The result object to format
    # @return [String] Formatted text output
    def format_as_text(result)
      formatter = Formatters::TextFormatter.new
      formatter.format(result)
    end

    # Handle errors based on verbosity settings.
    #
    # @param error [Error, Errno::ENOENT] The error to handle
    def handle_error(error)
      raise error if options[:verbose]

      # Convert Errno::ENOENT to user-friendly message
      if error.is_a?(Errno::ENOENT)
      end
      message = error.message

      warn message unless options[:quiet]
      exit 1
    end
  end
end
