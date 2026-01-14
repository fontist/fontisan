# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "fileutils"

require "rubocop/rake_task"

RuboCop::RakeTask.new

# rubocop:disable Metrics/BlockLength
namespace :fixtures do
  # Load centralized fixture configuration
  require_relative "spec/support/fixture_fonts"

  # Helper method to download a single file
  def download_single_file(name, url, target_path)
    require "open-uri"

    puts "[fixtures:download] Downloading #{name}..."
    FileUtils.mkdir_p(File.dirname(target_path))

    URI.open(url) do |remote|
      File.binwrite(target_path, remote.read)
    end

    puts "[fixtures:download] #{name} downloaded successfully"
  end

  # Helper method to download and extract a font archive
  def download_font(name, url, target_dir)
    require "open-uri"
    require "zip"

    puts "[fixtures:download] Downloading #{name}..."
    FileUtils.mkdir_p(target_dir)

    # Create a manual temp file path - OS will clean up temp files automatically
    temp_path = File.join(Dir.tmpdir,
                          "fontisan_#{name}_#{Process.pid}_#{rand(10000)}.zip")

    # Download using IO.copy_stream for better Windows compatibility
    URI.open(url, "rb") do |remote|
      File.open(temp_path, "wb") do |file|
        IO.copy_stream(remote, file)
      end
    end

    puts "[fixtures:download] Extracting #{name}..."

    # Open zip file and ensure it's fully closed before we're done
    zip_file = Zip::File.open(temp_path)
    begin
      zip_file.each do |entry|
        # Skip macOS metadata files and directories
        next if entry.name.start_with?("__MACOSX/") || entry.name.include?("/._")
        next if entry.directory?

        # Ensure entry.name is relative by stripping leading slashes
        relative_name = entry.name.sub(%r{^/+}, "")

        dest_path = File.join(target_dir, relative_name)
        FileUtils.mkdir_p(File.dirname(dest_path))

        # Skip if file already exists
        next if File.exist?(dest_path)

        # Write the file content directly using binary mode
        File.open(dest_path, "wb") do |file|
          IO.copy_stream(entry.get_input_stream, file)
        end
      end
    ensure
      # Explicitly close the zip file to release file handle on Windows
      zip_file&.close
    end

    # Temp file left in Dir.tmpdir - OS will clean it up automatically

    puts "[fixtures:download] #{name} downloaded successfully"
  rescue LoadError => e
    warn "[fixtures:download] Error: Required gem not installed. Please run: gem install rubyzip"
    raise e
  end

  # Get font configurations from centralized source
  fonts = FixtureFonts.rakefile_config

  # Create file tasks for each font
  fonts.each do |name, config|
    # Skip fonts that should not be downloaded (already committed)
    next if config[:skip_download]

    file config[:marker] do
      if config[:single_file]
        download_single_file(name, config[:url], config[:marker])
      else
        download_font(name, config[:url], config[:target_dir])
      end
    end
  end

  # Compute download task prerequisites (marker files for non-skipped fonts)
  download_prerequisites = fonts.values.reject do |config|
    config[:skip_download]
  end.map { |config| config[:marker] }

  desc "Download all test fixture fonts"
  task download: download_prerequisites

  desc "Clean downloaded fixtures"
  task :clean do
    fonts.values.reject { |config| config[:skip_download] }.each do |config|
      if config[:single_file]
        # For single files, just delete the marker file itself
        if File.exist?(config[:marker])
          puts "[fixtures:clean] Removing #{config[:marker]}..."
          FileUtils.rm_f(config[:marker])
          puts "[fixtures:clean] Removed #{config[:marker]}"
        end
      elsif File.exist?(config[:target_dir])
        # For archives, delete the entire target directory
        puts "[fixtures:clean] Removing #{config[:target_dir]}..."
        FileUtils.rm_rf(config[:target_dir])
        puts "[fixtures:clean] Removed #{config[:target_dir]}"
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength

# RSpec task depends on fixtures
RSpec::Core::RakeTask.new(spec: "fixtures:download")

# Default task runs spec and rubocop
task default: %i[spec rubocop]
