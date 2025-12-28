# frozen_string_literal: true

require "fontisan"
require "tempfile"

# Define the fixtures directory constant for test files
FIXTURES_DIR = File.join(__dir__, "fixtures")

# Check if test fixtures exist, download if missing
REQUIRED_FIXTURES = [
  File.join(FIXTURES_DIR, "fonts/NotoSans-Regular.ttf"),
  File.join(FIXTURES_DIR, "fonts/libertinus/Libertinus-7.051/static/OTF/LibertinusSerif-Regular.otf"),
  File.join(FIXTURES_DIR, "fonts/MonaSans/fonts/variable/MonaSansVF[wdth,wght,opsz].ttf"),
  File.join(FIXTURES_DIR, "fonts/MonaSans/fonts/static/ttf/MonaSans-ExtraLightItalic.ttf"),
  File.join(FIXTURES_DIR, "fonts/NotoSerifCJK/NotoSerifCJK.ttc"),
  File.join(FIXTURES_DIR, "fonts/NotoSerifCJK-VF/Variable/OTC/NotoSerifCJK-VF.otf.ttc"),
].freeze

unless REQUIRED_FIXTURES.all? { |f| File.exist?(f) }
  warn "Test fixtures not found. Downloading..."
  require "rake"
  Rake.application.rake_require "Rakefile", [File.expand_path("../Rakefile", __dir__)]
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
    def fixture_path(relative_path)
      File.join(FIXTURES_DIR, relative_path)
    end
  end)
end
