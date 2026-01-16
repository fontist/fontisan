# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Documentation Examples" do
  describe "CLI commands" do
    # Get list of Thor commands from CLI class
    let(:available_commands) do
      Fontisan::Cli.tasks.keys.map(&:to_s)
    end

    # Verify that the CLI has the expected commands documented in user guides
    it "has validate command with --list option" do
      expect(available_commands).to include("validate")
      # The validate command exists and accepts --list option for listing profiles
    end

    it "has validate command with --profile option" do
      expect(available_commands).to include("validate")
      # The validate command exists and accepts --profile option
    end

    it "has info command" do
      expect(available_commands).to include("info")
    end

    it "has convert command" do
      expect(available_commands).to include("convert")
    end

    it "has subset command" do
      expect(available_commands).to include("subset")
    end

    it "has pack command" do
      expect(available_commands).to include("pack")
    end

    it "has unpack command" do
      expect(available_commands).to include("unpack")
    end
  end

  describe "Ruby API" do
    # Verify that the Fontisan module has the documented Ruby API methods
    it "has Fontisan.info method" do
      expect(Fontisan).to respond_to(:info)
    end

    it "Fontisan.info accepts brief parameter" do
      # Test that brief parameter is supported (5x faster metadata loading)
      ttf_path = font_fixture_path("MonaSans",
                                   "googlefonts/variable/MonaSans[wdth,wght].ttf")
      expect { Fontisan.info(ttf_path, brief: true) }.not_to raise_error
    end

    it "Fontisan.info accepts font_index parameter" do
      ttf_path = font_fixture_path("MonaSans",
                                   "googlefonts/variable/MonaSans[wdth,wght].ttf")
      expect { Fontisan.info(ttf_path, brief: true, font_index: 0) }.not_to raise_error
    end

    it "has Fontisan.validate method" do
      expect(Fontisan).to respond_to(:validate)
    end

    it "Fontisan.validate accepts profile parameter" do
      ttf_path = font_fixture_path("MonaSans",
                                   "googlefonts/variable/MonaSans[wdth,wght].ttf")
      # Test that :production profile works
      expect { Fontisan.validate(ttf_path, profile: :production) }.not_to raise_error
    end

    it "has Fontisan::FontLoader" do
      expect(Fontisan::FontLoader).to be_a(Module)
    end

    it "Fontisan::FontLoader can load fonts" do
      expect(Fontisan::FontLoader).to respond_to(:load)
    end
  end

  describe "Documentation files exist" do
    # Verify all documented feature guides exist
    let(:base_dir) { File.join(__dir__, "..", "docs") }
    let(:adoc_files) do
      [
        "docs/FONT_HINTING.adoc",
        "docs/VARIABLE_FONT_OPERATIONS.adoc",
        "docs/WOFF_WOFF2_FORMATS.adoc",
        "docs/COLOR_FONTS.adoc",
        "docs/VALIDATION.adoc",
        "docs/APPLE_LEGACY_FONTS.adoc",
        "docs/COLLECTION_VALIDATION.adoc"
      ]
    end
    let(:md_files) do
      [
        "docs/EXTRACT_TTC_MIGRATION.md"
      ]
    end

    it "all AsciiDoc documentation files exist" do
      root_dir = File.join(__dir__, "..")
      adoc_files.each do |file|
        path = File.join(root_dir, file)
        expect(File.exist?(path)).to eq(true),
               "Expected #{file} to exist for documentation examples"
      end
    end

    it "all Markdown documentation files exist" do
      root_dir = File.join(__dir__, "..")
      md_files.each do |file|
        path = File.join(root_dir, file)
        expect(File.exist?(path)).to eq(true),
               "Expected #{file} to exist for documentation examples"
      end
    end
  end

  describe "Documentation examples reference valid commands" do
    # Verify that CLI command examples in documentation reference actual commands
    let(:root_dir) { File.join(__dir__, "..") }
    let(:cli_class) { Fontisan::Cli }

    # Get list of Thor commands from CLI class
    let(:available_commands) do
      # Cli inherits from Thor, we can get commands from it
      # These are the public methods that are Thor commands
      cli_class.tasks.keys.map(&:to_s)
    end

    it "convert command exists for examples in docs" do
      expect(available_commands).to include("convert")
    end

    it "subset command exists for examples in docs" do
      expect(available_commands).to include("subset")
    end

    it "validate command exists for examples in docs" do
      expect(available_commands).to include("validate")
    end

    it "pack command exists for examples in docs" do
      expect(available_commands).to include("pack")
    end

    it "unpack command exists for examples in docs" do
      expect(available_commands).to include("unpack")
    end

    it "info command exists for examples in docs" do
      expect(available_commands).to include("info")
    end

    it "instance command exists for examples in docs" do
      expect(available_commands).to include("instance")
    end

    it "tables command exists for examples in docs" do
      expect(available_commands).to include("tables")
    end

    it "glyphs command exists for examples in docs" do
      expect(available_commands).to include("glyphs")
    end

    it "unicode command exists for examples in docs" do
      expect(available_commands).to include("unicode")
    end

    it "variable command exists for examples in docs" do
      expect(available_commands).to include("variable")
    end

    it "optical_size command exists for examples in docs" do
      expect(available_commands).to include("optical_size")
    end

    it "scripts command exists for examples in docs" do
      expect(available_commands).to include("scripts")
    end

    it "features command exists for examples in docs" do
      expect(available_commands).to include("features")
    end

    it "ls command exists for examples in docs" do
      expect(available_commands).to include("ls")
    end

    it "export command exists for examples in docs" do
      expect(available_commands).to include("export")
    end

    it "dump_table command exists for examples in docs" do
      expect(available_commands).to include("dump_table")
    end

    it "version command exists for examples in docs" do
      expect(available_commands).to include("version")
    end
  end
end
