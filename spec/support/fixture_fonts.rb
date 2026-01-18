# frozen_string_literal: true

# Centralized fixture font configuration
# This is the single source of truth for all font fixture paths and download configuration.
# When font versions change, only update this file - tests remain unchanged.

module FixtureFonts
  FIXTURES_BASE = File.expand_path(File.join(__dir__, "..", "fixtures",
                                             "fonts"))

  # Font fixture configuration
  # Each font has:
  # - url: Download URL
  # - target_dir: Where to extract (relative to FIXTURES_BASE)
  # - path_prefix: Prefix added to logical paths (handles version-specific directory structures)
  # - markers: Files that must exist to consider the font downloaded
  FONTS = {
    "SourceSans3" => {
      url: "https://github.com/adobe-fonts/source-sans/releases/download/3.052R/OTF-source-sans-3.052R.zip",
      target_dir: "SourceSans3",
      path_prefix: "OTF", # Archive extracts to OTF-source-sans-3.052R/
      markers: ["OTF/SourceSans3-Regular.otf"],
    },
    "NotoSans" => {
      url: "https://github.com/notofonts/notofonts.github.io/raw/refs/heads/main/fonts/NotoSans/full/ttf/NotoSans-Regular.ttf",
      target_dir: "NotoSans",
      path_prefix: "", # Single file, no prefix needed
      single_file: true,
      markers: ["NotoSans-Regular.ttf"],
    },
    "Libertinus" => {
      url: "https://github.com/alerque/libertinus/releases/download/v7.051/Libertinus-7.051.zip",
      target_dir: "Libertinus",
      path_prefix: "Libertinus-7.051", # Archive extracts to Libertinus-7.051/
      markers: ["Libertinus-7.051/static/OTF/LibertinusSerif-Regular.otf"],
    },
    "MonaSans" => {
      url: "https://github.com/github/mona-sans/archive/refs/tags/2.0.8.zip",
      target_dir: "MonaSans",
      path_prefix: "mona-sans-2.0.8", # Archive extracts to mona-sans-2.0.8/
      markers: [
        "mona-sans-2.0.8/fonts/variable/MonaSansVF[wdth,wght,opsz,ital].ttf",
        "mona-sans-2.0.8/fonts/static/ttf/MonaSans-ExtraLightItalic.ttf",
      ],
    },
    "NotoSerifCJK" => {
      url: "https://github.com/notofonts/noto-cjk/releases/download/Serif2.003/01_NotoSerifCJK.ttc.zip",
      target_dir: "NotoSerifCJK",
      path_prefix: "", # Extracts directly
      markers: ["NotoSerifCJK.ttc"],
    },
    "NotoSerifCJK-VF" => {
      url: "https://github.com/notofonts/noto-cjk/releases/download/Serif2.003/02_NotoSerifCJK-OTF-VF.zip",
      target_dir: "NotoSerifCJK-VF",
      path_prefix: "", # Extracts directly
      markers: ["Variable/OTC/NotoSerifCJK-VF.otf.ttc"],
    },
    "DinaRemasterII" => {
      url: "https://github.com/zshoals/Dina-Font-TTF-Remastered/raw/refs/heads/master/Fonts/DinaRemasterII.ttc",
      target_dir: "DinaRemasterII",
      path_prefix: "", # Single file, no prefix
      single_file: true,
      markers: ["DinaRemasterII.ttc"],
    },
    "EmojiOneColor" => {
      url: "https://github.com/adobe-fonts/emojione-color/raw/master/EmojiOneColor.otf",
      target_dir: "EmojiOneColor",
      path_prefix: "", # Single file, no prefix
      single_file: true,
      markers: ["EmojiOneColor.otf"],
    },
    "TwitterColorEmoji" => {
      url: "https://github.com/13rac1/twemoji-color-font/releases/download/v15.1.0/TwitterColorEmoji-SVGinOT-15.1.0.zip",
      target_dir: "TwitterColorEmoji",
      path_prefix: "TwitterColorEmoji-SVGinOT-15.1.0",
      markers: ["TwitterColorEmoji-SVGinOT-15.1.0/TwitterColorEmoji-SVGinOT.ttf"],
    },
    "Gilbert" => {
      url: "https://github.com/Fontself/TypeWithPride/releases/download/1.005/Gilbert_1.005_alpha.zip",
      target_dir: "Gilbert",
      path_prefix: "",
      markers: ["Gilbert-Color Bold Preview5.otf"],
    },
    "TwemojiMozilla" => {
      url: "https://github.com/mozilla/twemoji-colr/releases/download/v0.7.0/Twemoji.Mozilla.ttf",
      target_dir: "TwemojiMozilla",
      path_prefix: "",
      single_file: true,
      markers: ["Twemoji.Mozilla.ttf"],
    },
    "Tamsyn" => {
      url: "https://github.com/roman0x58/tamsyn-mac-version/archive/refs/tags/0.1.zip",
      target_dir: "tamsyn",
      path_prefix: "tamsyn-mac-version-0.1/tamsyn",
      markers: ["tamsyn-mac-version-0.1/tamsyn/Tamsyn7x13.dfont"],
    },
    "UnifontEX" => {
      url: "https://github.com/stgiga/UnifontEX/raw/refs/heads/main/UnifontExMono.dfont",
      target_dir: "unifontex",
      path_prefix: "",
      single_file: true,
      markers: ["UnifontExMono.dfont"],
    },
    "URWBase35" => {
      url: "https://github.com/ArtifexSoftware/urw-base35-fonts/archive/refs/tags/20230902.zip",
      target_dir: "type1/urw",
      path_prefix: "urw-base35-fonts-20230902", # Archive extracts to urw-base35-fonts-20230902/
      markers: ["urw-base35-fonts-20230902/fonts/C059-Bold.ttf"],
    },
  }.freeze

  # Get absolute path to a font fixture file
  # @param font_name [String] Font name (e.g., "MonaSans")
  # @param relative_path [String] Logical path within font (e.g., "static/ttf/MonaSans-Bold.ttf")
  # @return [String] Absolute path to the font file
  def self.path(font_name, relative_path)
    config = FONTS[font_name]
    raise ArgumentError, "Unknown font: #{font_name}" unless config

    base = File.join(FIXTURES_BASE, config[:target_dir])

    # Add path_prefix if present (handles version-specific directory structures)
    if config[:path_prefix] && !config[:path_prefix].empty?
      File.join(base, config[:path_prefix], relative_path)
    else
      File.join(base, relative_path)
    end
  end

  # Get all required marker files (for checking if fonts are downloaded)
  # @return [Array<String>] Array of absolute paths to marker files
  def self.required_markers
    FONTS.flat_map do |_name, config|
      base = File.join(FIXTURES_BASE, config[:target_dir])
      config[:markers].map { |marker| File.join(base, marker) }
    end
  end

  # Get Rakefile-compatible font configuration
  # @return [Hash] Hash suitable for Rakefile download tasks
  def self.rakefile_config
    FONTS.transform_values do |config|
      base = File.join(FIXTURES_BASE, config[:target_dir])
      {
        url: config[:url],
        target_dir: base,
        marker: File.join(base, config[:markers].first), # Use first marker for Rake task
        single_file: config[:single_file] || false,
        skip_download: config[:skip_download] || false,
      }
    end
  end
end
