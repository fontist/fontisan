# frozen_string_literal: true

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
