# frozen_string_literal: true

module Fontisan
  module Type1
    # INF (Font Information) Generator
    #
    # [`INFGenerator`](lib/fontisan/type1/inf_generator.rb) generates INF files
    # for Windows Type 1 font installation.
    #
    # INF files contain metadata for installing Type 1 fonts on Windows systems.
    # They reference the PFB, PFM, and AFM files that make up a Windows Type 1 font.
    #
    # @example Generate INF from TTF
    #   font = Fontisan::FontLoader.load("font.ttf")
    #   inf_data = Fontisan::Type1::INFGenerator.generate(font)
    #   File.write("font.inf", inf_data)
    #
    # @example Generate INF with custom file names
    #   inf_data = Fontisan::Type1::INFGenerator.generate(font,
    #     pfb_file: "myfont.pfb",
    #     afm_file: "myfont.afm",
    #     pfm_file: "myfont.pfm"
    #   )
    #
    # @see https://www.adobe.com/devnet/font/pdfs/5005.PFM_Spec.pdf
    class INFGenerator
      # Generate INF file content from a font
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate INF from
      # @param options [Hash] Generation options
      # @option options [String] :pfb_file PFB filename (default: based on font name)
      # @option options [String] :afm_file AFM filename (default: based on font name)
      # @option options [String] :pfm_file PFM filename (default: based on font name)
      # @option options [String] :inf_file INF filename (default: based on font name)
      # @option options [String] :otf_file OTF filename (for OpenType fonts)
      # @return [String] INF file content
      def self.generate(font, options = {})
        new(font, options).generate
      end

      # Generate INF file from a font and write to file
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate INF from
      # @param path [String] Path to write INF file
      # @param options [Hash] Generation options
      # @return [void]
      def self.generate_to_file(font, path, options = {})
        inf_content = generate(font, options)
        File.write(path, inf_content, encoding: "ISO-8859-1")
      end

      # Initialize a new INFGenerator
      #
      # @param font [Fontisan::TrueTypeFont, Fontisan::OpenTypeFont] The font to generate INF from
      # @param options [Hash] Generation options
      def initialize(font, options = {})
        @font = font
        @options = options
        @metrics = MetricsCalculator.new(font)
      end

      # Generate INF file content
      #
      # @return [String] INF file content
      def generate
        lines = []

        # Font description section
        lines << "[Font Description]"
        lines << build_font_description
        lines << ""

        # Files section
        lines << "[Files]"
        lines << build_file_list
        lines << ""

        # Other section
        lines << "[Other]"
        lines << build_other_section

        lines.join("\n")
      end

      private

      # Build font description section
      #
      # @return [String] Font description lines
      def build_font_description
        lines = []

        # Font name (required)
        font_name = extract_font_name
        lines << "FontName=#{font_name}"

        # Font files
        pfb_file = @options[:pfb_file] || default_pfb_file
        lines << "FontFile=#{pfb_file}"

        afm_file = @options[:afm_file] || default_afm_file
        lines << "MetricsFile=#{afm_file}"

        pfm_file = @options[:pfm_file] || default_pfm_file
        lines << "WinMetricsFile=#{pfm_file}"

        # Font family
        family_name = extract_family_name
        lines << "FamilyName=#{family_name}" if family_name

        # Font weight
        weight = extract_weight
        lines << "Weight=#{weight}" if weight

        # Italic angle
        italic_angle = extract_italic_angle
        lines << "ItalicAngle=#{italic_angle}" if italic_angle && italic_angle != 0

        # Version
        version = extract_version
        lines << "Version=#{version}" if version

        # Copyright
        copyright = extract_copyright
        lines << "Copyright=#{copyright}" if copyright

        # Font type
        lines << "FontType=Type 1"

        lines.join("\n")
      end

      # Build file list section
      #
      # @return [String] File list lines
      def build_file_list
        lines = []

        # PFB file (required)
        pfb_file = @options[:pfb_file] || default_pfb_file
        lines << "#{pfb_file}=PFB"

        # AFM file (required)
        afm_file = @options[:afm_file] || default_afm_file
        lines << "#{afm_file}=AFM"

        # PFM file (required for Windows)
        pfm_file = @options[:pfm_file] || default_pfm_file
        lines << "#{pfm_file}=PFM"

        # OTF file (if converting from OTF)
        if @options[:otf_file]
          lines << "#{@options[:otf_file]}=OTF"
        end

        lines.join("\n")
      end

      # Build other section
      #
      # @return [String] Other section lines
      def build_other_section
        lines = []

        # Installation notes
        lines << "Notes=This font is generated from #{@font.post_script_name} by Fontisan"

        # Vendor
        vendor = extract_vendor
        lines << "Vendor=#{vendor}" if vendor

        # License
        license = extract_license
        lines << "License=#{license}" if license

        lines.join("\n")
      end

      # Extract font name
      #
      # @return [String] Font name
      def extract_font_name
        name_table = @font.table(Constants::NAME_TAG)
        return "" unless name_table

        # Try full font name first, then postscript name
        if name_table.respond_to?(:full_font_name)
          name_table.full_font_name(1) || name_table.full_font_name(3) ||
            extract_postscript_name
        else
          extract_postscript_name
        end
      end

      # Extract PostScript name
      #
      # @return [String] PostScript name
      def extract_postscript_name
        name_table = @font.table(Constants::NAME_TAG)
        return @font.post_script_name || "Unknown" unless name_table

        if name_table.respond_to?(:postscript_name)
          name_table.postscript_name(1) || name_table.postscript_name(3) ||
            @font.post_script_name || "Unknown"
        else
          @font.post_script_name || "Unknown"
        end
      end

      # Extract family name
      #
      # @return [String, nil] Family name
      def extract_family_name
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:font_family)
          name_table.font_family(1) || name_table.font_family(3)
        end
      end

      # Extract weight
      #
      # @return [String, nil] Weight
      def extract_weight
        os2 = @font.table(Constants::OS2_TAG)
        return nil unless os2

        weight_class = if os2.respond_to?(:us_weight_class)
                         os2.us_weight_class
                       elsif os2.respond_to?(:weight_class)
                         os2.weight_class
                       end
        return nil unless weight_class

        case weight_class
        when 100..200 then "Thin"
        when 200..300 then "ExtraLight"
        when 300..400 then "Light"
        when 400..500 then "Regular"
        when 500..600 then "Medium"
        when 600..700 then "SemiBold"
        when 700..800 then "Bold"
        when 800..900 then "ExtraBold"
        when 900..1000 then "Black"
        else "Regular"
        end
      end

      # Extract italic angle
      #
      # @return [Float, nil] Italic angle
      def extract_italic_angle
        post = @font.table(Constants::POST_TAG)
        return nil unless post

        if post.respond_to?(:italic_angle)
          post.italic_angle
        end
      end

      # Extract version
      #
      # @return [String, nil] Version string
      def extract_version
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:version_string)
          name_table.version_string(1) || name_table.version_string(3)
        end
      end

      # Extract copyright
      #
      # @return [String, nil] Copyright notice
      def extract_copyright
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:copyright)
          name_table.copyright(1) || name_table.copyright(3)
        end
      end

      # Extract vendor/manufacturer
      #
      # @return [String, nil] Vendor name
      def extract_vendor
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:manufacturer)
          name_table.manufacturer(1) || name_table.manufacturer(3)
        end
      end

      # Extract license information
      #
      # @return [String, nil] License information
      def extract_license
        name_table = @font.table(Constants::NAME_TAG)
        return nil unless name_table

        if name_table.respond_to?(:license)
          name_table.license(1) || name_table.license(3)
        end
      end

      # Get default PFB filename
      #
      # @return [String] PFB filename
      def default_pfb_file
        "#{extract_postscript_name}.pfb"
      end

      # Get default AFM filename
      #
      # @return [String] AFM filename
      def default_afm_file
        "#{extract_postscript_name}.afm"
      end

      # Get default PFM filename
      #
      # @return [String] PFM filename
      def default_pfm_file
        "#{extract_postscript_name}.pfm"
      end
    end
  end
end
