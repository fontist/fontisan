# frozen_string_literal: true

# RSpec Configuration and Test Fixture Management
#
# This file configures the RSpec test suite with automatic font fixture management.
#
# == Fixture Requirements
#
# All tests require font fixtures to be downloaded before running. The test suite uses
# a centralized fixture configuration system (spec/support/fixture_fonts.rb) that defines
# all required fonts and their download sources.
#
# == Automatic Fixture Download
#
# Fixtures are automatically downloaded when running tests via:
#   - `bundle exec rspec` (downloads fixtures before running tests)
#   - `bundle exec rake spec` (depends on fixtures:download task)
#   - `bundle exec rake` (default task runs spec)
#
# Manual fixture management:
#   - Download all fixtures: `bundle exec rake fixtures:download`
#   - Clean fixtures: `bundle exec rake fixtures:clean`
#
# == Available Fixture Fonts
#
# The following fonts are automatically downloaded and available for testing:
#
# - SourceSans3: Adobe Source Sans 3 (OTF, has GSUB features)
# - NotoSans: Google Noto Sans (TTF, has GSUB, hints, standard tables)
# - Libertinus: Libertinus fonts (TTF/OTF, has GSUB, hints, compound glyphs)
# - MonaSans: GitHub Mona Sans (TTF/OTF, static and variable, has GSUB)
# - NotoSerifCJK: Noto Serif CJK (TTC, 35 fonts, large collection)
# - NotoSerifCJK-VF: Noto Serif CJK Variable (OTC, variable fonts)
# - DinaRemasterII: Dina font remaster (TTC, 2 fonts, bitmap strikes)
# - EmojiOneColor: Emoji color font (OTF, COLR/CPAL tables)
# - TwitterColorEmoji: Twitter Emoji (TTF, SVG-in-OpenType)
# - Gilbert: Gilbert color font (OTF, COLR tables)
# - TwemojiMozilla: Mozilla Twemoji (TTF, COLR/CPAL v1)
# - Tamsyn: Tamsyn bitmap font (dfont, Apple suitcase format)
# - UnifontEX: GNU Unifont Extended (dfont, large Unicode coverage)
#
# == Font Feature Matrix
#
# Feature support by fixture font:
#
# | Font           | GSUB | Hints | Compound | COLR | SVG | Variable | Collections |
# |----------------|------|-------|----------|------|-----|----------|-------------|
# | SourceSans3    | Yes  | CFF   | Yes      | No   | No  | No       | No          |
# | NotoSans       | Yes  | Yes   | Yes      | No   | No  | No       | No          |
# | Libertinus     | Yes  | Yes   | Yes      | No   | No  | No       | No          |
# | MonaSans       | Yes  | Yes   | Yes      | No   | No  | Yes      | No          |
# | NotoSerifCJK   | Yes  | Yes   | Yes      | No   | No  | No       | Yes (35)    |
# | DinaRemasterII | No   | Yes   | Yes      | No   | No  | No       | Yes (2)     |
# | EmojiOneColor  | No   | No    | Yes      | Yes  | No  | No       | No          |
# | TwitterEmoji   | No   | Yes   | Yes      | No   | Yes | No       | No          |
# | TwemojiMozilla | No   | Yes   | Yes      | Yes  | No  | No       | No          |
#
# == Test Requirements
#
# Tests assume fixtures are present and will FAIL (not skip) if:
# - Required fonts are not downloaded
# - Required tables are missing from fonts
# - Required font features are not present
#
# This ensures complete test coverage and prevents silent test skipping.
# Run `bundle exec rake fixtures:download` if tests fail due to missing fixtures.

require "fontisan"
require "tempfile"

# Load centralized fixture configuration
require_relative "support/fixture_fonts"

# Define the fixtures directory constant for test files
FIXTURES_DIR = File.join(__dir__, "fixtures")

# Check if test fixtures exist, download if missing
unless FixtureFonts.required_markers.all? { |f| File.exist?(f) }
  warn "Test fixtures not found. Downloading..."
  require "rake"
  rakefile_path = File.expand_path("../Rakefile", __dir__)
  load rakefile_path
  Rake::Task["fixtures:download"].invoke
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Add fixture_path helper method
  config.include(Module.new do
    # Legacy helper - maintains backward compatibility
    # @param relative_path [String] Path relative to fixtures/fonts/
    def fixture_path(relative_path)
      File.join(FIXTURES_DIR, relative_path)
    end

    # New helper - uses centralized configuration
    # @param font_name [String] Font name (e.g., "MonaSans")
    # @param relative_path [String] Logical path within font (e.g., "static/ttf/MonaSans-Bold.ttf")
    # @return [String] Absolute path to font file
    #
    # @example
    #   font_fixture_path("MonaSans", "static/ttf/MonaSans-ExtraLightItalic.ttf")
    #   # => "/path/to/spec/fixtures/fonts/MonaSans/mona-sans-2.0.8/static/ttf/MonaSans-ExtraLightItalic.ttf"
    def font_fixture_path(font_name, relative_path)
      FixtureFonts.path(font_name, relative_path)
    end
  end)
end
