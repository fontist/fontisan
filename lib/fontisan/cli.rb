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

    desc "ls FILE", "List contents (fonts in collection or font summary)"
    # List contents of font files with auto-detection.
    #
    # For collections (TTC/OTC): Lists all fonts in the collection
    # For individual fonts (TTF/OTF): Shows quick font summary
    #
    # @param file [String] Path to the font or collection file
    #
    # @example List fonts in collection
    #   fontisan ls fonts.ttc
    #
    # @example Show font summary
    #   fontisan ls font.ttf
    def ls(file)
      command = Commands::LsCommand.new(file, options)
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

    desc "subset FONT_FILE", "Subset a font to specific glyphs"
    option :text, type: :string,
                  desc: "Text to subset (e.g., 'Hello World')",
                  aliases: "-t"
    option :glyphs, type: :string,
                    desc: "Comma-separated glyph IDs (e.g., '0,1,65,66,67')",
                    aliases: "-g"
    option :unicode, type: :string,
                     desc: "Comma-separated Unicode codepoints (e.g., 'U+0041,U+0042' or '0x41,0x42')",
                     aliases: "-u"
    option :output, type: :string, required: true,
                    desc: "Output file path",
                    aliases: "-o"
    option :profile, type: :string, default: "pdf",
                     desc: "Subsetting profile (pdf, web, minimal)",
                     aliases: "-p"
    option :retain_gids, type: :boolean, default: false,
                         desc: "Retain original glyph IDs (leave gaps)"
    option :drop_hints, type: :boolean, default: false,
                        desc: "Drop hinting instructions"
    option :drop_names, type: :boolean, default: false,
                        desc: "Drop glyph names from post table"
    option :unicode_ranges, type: :boolean, default: true,
                            desc: "Prune OS/2 Unicode ranges"
    # Subset a font to specific glyphs.
    #
    # You must specify one of --text, --glyphs, or --unicode to define
    # which glyphs to include in the subset.
    #
    # @param font_file [String] Path to the font file
    def subset(font_file)
      command = Commands::SubsetCommand.new(font_file, options)
      result = command.run

      unless options[:quiet]
        puts "Subset font created:"
        puts "  Input: #{result[:input]}"
        puts "  Output: #{result[:output]}"
        puts "  Original glyphs: #{result[:original_glyphs]}"
        puts "  Subset glyphs: #{result[:subset_glyphs]}"
        puts "  Profile: #{result[:profile]}"
        puts "  Size: #{format_size(result[:size])}"
      end
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "convert FONT_FILE", "Convert font to different format"
    option :to, type: :string, required: true,
                desc: "Target format (ttf, otf, woff2, svg)",
                aliases: "-t"
    option :output, type: :string, required: true,
                    desc: "Output file path",
                    aliases: "-o"
    option :optimize, type: :boolean, default: false,
                      desc: "Optimize CFF with subroutines (TTF→OTF only)"
    option :min_pattern_length, type: :numeric, default: 10,
                                desc: "Minimum pattern length for subroutines"
    option :max_subroutines, type: :numeric, default: 65_535,
                             desc: "Maximum number of subroutines"
    option :optimize_ordering, type: :boolean, default: true,
                               desc: "Optimize subroutine ordering by frequency"
    # Convert a font to a different format.
    #
    # Supported conversions:
    # - Same format (ttf→ttf, otf→otf): Copy/optimize
    # - TTF ↔ OTF: Outline format conversion (foundation)
    # - Future: WOFF2 compression, SVG export
    #
    # Subroutine Optimization (--optimize):
    # When converting TTF→OTF, you can enable automatic CFF subroutine generation
    # to reduce file size. This analyzes repeated byte patterns across glyphs and
    # creates shared subroutines, typically saving 30-50% in CFF table size.
    #
    # @param font_file [String] Path to the font file
    #
    # @example Convert TTF to OTF
    #   fontisan convert font.ttf --to otf --output font.otf
    #
    # @example Convert with optimization
    #   fontisan convert font.ttf --to otf --output font.otf --optimize --verbose
    #
    # @example Convert with custom optimization parameters
    #   fontisan convert font.ttf --to otf --output font.otf --optimize \
    #     --min-pattern-length 15 --max-subroutines 10000
    #
    # @example Copy/optimize TTF
    #   fontisan convert font.ttf --to ttf --output optimized.ttf
    def convert(font_file)
      command = Commands::ConvertCommand.new(font_file, options)
      command.run
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "instance FONT_FILE",
         "Generate static font instance from variable font"
    option :output, type: :string,
                    desc: "Output file path",
                    aliases: "-o"
    option :wght, type: :numeric,
                  desc: "Weight axis value"
    option :wdth, type: :numeric,
                  desc: "Width axis value"
    option :slnt, type: :numeric,
                  desc: "Slant axis value"
    option :ital, type: :numeric,
                  desc: "Italic axis value"
    option :opsz, type: :numeric,
                  desc: "Optical size axis value"
    option :named_instance, type: :string,
                            desc: "Use named instance (e.g., 'Bold', 'Light')",
                            aliases: "-n"
    option :list_instances, type: :boolean, default: false,
                            desc: "List available named instances",
                            aliases: "-l"
    option :to, type: :string,
                desc: "Convert to format (ttf, otf, woff, woff2, svg)",
                aliases: "-t"
    # Generate static font instance from variable font.
    #
    # You can specify axis coordinates using --wght, --wdth, etc., or use
    # a predefined named instance with --named-instance. Use --list-instances
    # to see available named instances.
    #
    # @param font_file [String] Path to the variable font file
    #
    # @example Generate bold instance
    #   fontisan instance variable.ttf --wght=700 --output=bold.ttf
    #
    # @example Use named instance
    #   fontisan instance variable.ttf --named-instance="Bold" --output=bold.ttf
    #
    # @example Instance with format conversion
    #   fontisan instance variable.ttf --wght=700 --to=woff2 --output=bold.woff2
    #
    # @example List available instances
    #   fontisan instance variable.ttf --list-instances
    def instance(font_file)
      command = Commands::InstanceCommand.new
      command.execute(font_file, options)
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

    desc "validate FONT_FILE", "Validate font file structure and checksums"
    option :verbose, type: :boolean, default: false,
                     desc: "Show detailed validation information"
    def validate(font_file)
      command = Commands::ValidateCommand.new(font_file, verbose: options[:verbose])
      exit command.run
    end

    desc "export FONT_FILE", "Export font to TTX/YAML/JSON format"
    option :output, type: :string,
                    desc: "Output file path (default: stdout)",
                    aliases: "-o"
    option :format, type: :string, default: "yaml",
                    desc: "Export format (yaml, json, ttx)",
                    aliases: "-f"
    option :tables, type: :array,
                    desc: "Specific tables to export",
                    aliases: "-t"
    option :binary_format, type: :string, default: "hex",
                           desc: "Binary encoding (hex, base64)",
                           aliases: "-b"

    def export(font_file)
      command = Commands::ExportCommand.new(
        font_file,
        output: options[:output],
        format: options[:format].to_sym,
        tables: options[:tables],
        binary_format: options[:binary_format].to_sym,
      )
      exit command.run
    end

    desc "version", "Display version information"
    # Display the Fontisan version.
    def version
      puts "Fontisan version #{Fontisan::VERSION}"
    end

    desc "unpack FONT_FILE", "Unpack fonts from TTC/OTC collection"
    option :output_dir, type: :string, required: true,
                        desc: "Output directory for extracted fonts",
                        aliases: "-d"
    option :font_index, type: :numeric,
                        desc: "Extract specific font by index (default: extract all)",
                        aliases: "-i"
    option :format, type: :string,
                    desc: "Output format (ttf, otf, woff, woff2)",
                    aliases: "-f"
    option :prefix, type: :string,
                    desc: "Filename prefix for extracted fonts",
                    aliases: "-p"
    # Extract individual fonts from a TTC (TrueType Collection) or OTC (OpenType Collection) file.
    #
    # This command unpacks fonts from collection files, optionally converting them
    # to different formats during extraction.
    #
    # @param font_file [String] Path to the TTC/OTC collection file
    #
    # @example Extract all fonts to directory
    #   fontisan unpack family.ttc --output-dir extracted/
    #
    # @example Extract specific font by index
    #   fontisan unpack family.ttc --output-dir extracted/ --font-index 0
    #
    # @example Extract with format conversion
    #   fontisan unpack family.ttc --output-dir extracted/ --format woff2
    #
    # @example Extract with custom prefix
    #   fontisan unpack family.ttc --output-dir extracted/ --prefix "NotoSans"
    def unpack(font_file)
      command = Commands::UnpackCommand.new(font_file, options)
      result = command.run

      unless options[:quiet]
        puts "Collection unpacked successfully:"
        puts "  Input: #{result[:collection]}"
        puts "  Output directory: #{result[:output_dir]}"
        puts "  Fonts extracted: #{result[:fonts_extracted]}/#{result[:num_fonts]}"
        result[:extracted_files].each do |file|
          size = File.size(file)
          puts "  - #{File.basename(file)} (#{format_size(size)})"
        end
      end
    rescue Errno::ENOENT, Error => e
      handle_error(e)
    end

    desc "pack FONT_FILES...", "Pack multiple fonts into TTC/OTC collection"
    option :output, type: :string, required: true,
                    desc: "Output collection file path",
                    aliases: "-o"
    option :format, type: :string, default: "ttc",
                    desc: "Collection format (ttc, otc)",
                    aliases: "-f"
    option :optimize, type: :boolean, default: true,
                      desc: "Enable table sharing optimization",
                      aliases: "--optimize"
    option :analyze, type: :boolean, default: false,
                     desc: "Show analysis report before building",
                     aliases: "--analyze"
    # Create a TTC (TrueType Collection) or OTC (OpenType Collection) from multiple font files.
    #
    # This command combines multiple fonts into a single collection file with
    # shared table deduplication to save space. It supports both TTC and OTC formats.
    #
    # @param font_files [Array<String>] Paths to input font files (minimum 2 required)
    #
    # @example Pack fonts into TTC
    #   fontisan pack font1.ttf font2.ttf font3.ttf --output family.ttc
    #
    # @example Pack into OTC with analysis
    #   fontisan pack Regular.otf Bold.otf Italic.otf --output family.otc --analyze
    #
    # @example Pack without optimization
    #   fontisan pack font1.ttf font2.ttf --output collection.ttc --no-optimize
    def pack(*font_files)
      command = Commands::PackCommand.new(font_files, options)
      result = command.run

      unless options[:quiet]
        puts "Collection created successfully:"
        puts "  Output: #{result[:output]}"
        puts "  Format: #{result[:format].upcase}"
        puts "  Fonts: #{result[:num_fonts]}"
        puts "  Size: #{format_size(result[:output_size])}"
        if result[:space_savings].positive?
          puts "  Space saved: #{format_size(result[:space_savings])}"
          puts "  Sharing: #{result[:sharing_percentage]}%"
        end
      end
    rescue Errno::ENOENT, Error => e
      handle_error(e)
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

    # Format file size in human-readable form
    #
    # @param size [Integer] Size in bytes
    # @return [String] Formatted size
    def format_size(size)
      if size < 1024
        "#{size} bytes"
      elsif size < 1024 * 1024
        "#{(size / 1024.0).round(2)} KB"
      else
        "#{(size / (1024.0 * 1024)).round(2)} MB"
      end
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
