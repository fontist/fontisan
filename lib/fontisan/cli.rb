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

    desc "info PATH", "Display font information"
    option :brief, type: :boolean, default: false,
                   desc: "Brief mode - only essential info (5x faster, uses metadata loading)",
                   aliases: "-b"
    # Extract and display comprehensive font metadata.
    #
    # @param path [String] Path to the font file or collection
    def info(path)
      command = Commands::InfoCommand.new(path, options)
      info = command.run
      output_result(info) unless options[:quiet]
    rescue Errno::ENOENT
      if options[:verbose]
        raise
      else
        warn "File not found: #{path}" unless options[:quiet]
        exit 1
      end
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
                desc: "Target format (ttf, otf, woff, woff2)",
                aliases: "-t"
    option :output, type: :string, required: true,
                    desc: "Output file path",
                    aliases: "-o"
    option :coordinates, type: :string,
                         desc: "Instance coordinates (e.g., wght=700,wdth=100)",
                         aliases: "-c"
    option :instance_index, type: :numeric,
                            desc: "Named instance index",
                            aliases: "-n"
    option :preserve_variation, type: :boolean,
                                desc: "Force variation preservation (auto-detected by default)"
    option :no_validate, type: :boolean, default: false,
                         desc: "Skip output validation"
    option :preserve_hints, type: :boolean, default: false,
                            desc: "Preserve rendering hints during conversion (TTF→OTF preservations may be limited)"
    option :wght, type: :numeric,
                  desc: "Weight axis value (alternative to --coordinates)"
    option :wdth, type: :numeric,
                  desc: "Width axis value (alternative to --coordinates)"
    option :slnt, type: :numeric,
                  desc: "Slant axis value (alternative to --coordinates)"
    option :ital, type: :numeric,
                  desc: "Italic axis value (alternative to --coordinates)"
    option :opsz, type: :numeric,
                  desc: "Optical size axis value (alternative to --coordinates)"
    # Convert a font to a different format using the universal transformation pipeline.
    #
    # Supported conversions:
    # - TTF ↔ OTF: Outline format conversion
    # - WOFF/WOFF2: Web font packaging
    # - Variable fonts: Automatic variation preservation or instance generation
    #
    # Variable Font Operations:
    # The pipeline automatically detects whether variation data can be preserved based on
    # source and target formats. For same outline family (TTF→WOFF or OTF→WOFF2), variation
    # is preserved automatically. For cross-family conversions (TTF↔OTF), an instance is
    # generated unless --preserve-variation is explicitly set.
    #
    # Instance Generation:
    # Use --coordinates to specify exact axis values (e.g., wght=700,wdth=100) or
    # --instance-index to use a named instance. Individual axis options (--wght, --wdth)
    # are also supported for convenience.
    #
    # @param font_file [String] Path to the font file
    #
    # @example Convert TTF to OTF
    #   fontisan convert font.ttf --to otf --output font.otf
    #
    # @example Generate bold instance at specific coordinates
    #   fontisan convert variable.ttf --to ttf --output bold.ttf --coordinates "wght=700,wdth=100"
    #
    # @example Generate bold instance using individual axis options
    #   fontisan convert variable.ttf --to ttf --output bold.ttf --wght 700
    #
    # @example Use named instance
    #   fontisan convert variable.ttf --to woff2 --output bold.woff2 --instance-index 0
    #
    # @example Force variation preservation (if compatible)
    #   fontisan convert variable.ttf --to woff2 --output variable.woff2 --preserve-variation
    #
    # @example Convert without validation
    #   fontisan convert font.ttf --to otf --output font.otf --no-validate
    def convert(font_file)
      # Build instance coordinates from axis options
      instance_coords = build_instance_coordinates(options)

      # Merge coordinates into options
      convert_options = options.to_h.dup
      if instance_coords.any?
        convert_options[:instance_coordinates] =
          instance_coords
      end

      command = Commands::ConvertCommand.new(font_file, convert_options)
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

    desc "validate FONT_FILE", "Validate font file"
    long_desc <<-DESC
      Validate font file against quality checks and standards.

      Test lists (-t/--test-list):
        indexability     - Fast indexing validation
        usability        - Installation compatibility
        production       - Comprehensive quality (default)
        web              - Web font readiness
        spec_compliance  - OpenType spec compliance
        default          - Production profile (alias)

      Return values (with -R/--return-value-results):
        0  No results
        1  Execution errors
        2  Fatal errors found
        3  Major errors found
        4  Minor errors found
        5  Spec violations found
    DESC

    option :exclude, aliases: "-e", type: :array, desc: "Tests to exclude"
    option :list, aliases: "-l", type: :boolean, desc: "List available tests"
    option :output, aliases: "-o", type: :string, desc: "Output file"
    option :full_report, aliases: "-r", type: :boolean, desc: "Full report"
    option :return_value_results, aliases: "-R", type: :boolean, desc: "Use return value for results"
    option :summary_report, aliases: "-S", type: :boolean, desc: "Summary report"
    option :test_list, aliases: "-t", type: :string, default: "default", desc: "Tests to execute"
    option :table_report, aliases: "-T", type: :boolean, desc: "Tabular report"
    option :verbose, aliases: "-v", type: :boolean, desc: "Verbose output"
    option :suppress_warnings, aliases: "-W", type: :boolean, desc: "Suppress warnings"

    def validate(font_file)
      if options[:list]
        list_available_tests
        return
      end

      cmd = Commands::ValidateCommand.new(
        input: font_file,
        profile: options[:test_list],
        exclude: options[:exclude] || [],
        output: options[:output],
        format: options[:format].to_sym,
        full_report: options[:full_report],
        summary_report: options[:summary_report],
        table_report: options[:table_report],
        verbose: options[:verbose],
        suppress_warnings: options[:suppress_warnings],
        return_value_results: options[:return_value_results]
      )

      exit cmd.run
    rescue => e
      error "Validation failed: #{e.message}"
      exit 1
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

    # Build instance coordinates from CLI axis options
    #
    # @param options [Hash] CLI options
    # @return [Hash] Coordinates hash
    def build_instance_coordinates(options)
      coords = {}
      coords["wght"] = options[:wght].to_f if options[:wght]
      coords["wdth"] = options[:wdth].to_f if options[:wdth]
      coords["slnt"] = options[:slnt].to_f if options[:slnt]
      coords["ital"] = options[:ital].to_f if options[:ital]
      coords["opsz"] = options[:opsz].to_f if options[:opsz]
      coords
    end

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

    # List available validation tests/profiles
    #
    # @return [void]
    def list_available_tests
      require_relative "validators/profile_loader"
      profiles = Validators::ProfileLoader.all_profiles
      puts "Available validation profiles:"
      profiles.each do |profile_name, config|
        puts "  #{profile_name.to_s.ljust(20)} - #{config[:description]}"
      end
    end
  end
end
