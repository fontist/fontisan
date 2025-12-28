# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "fileutils"

require "rubocop/rake_task"

RuboCop::RakeTask.new

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

    zip_file = "#{target_dir}/#{name}.zip"

    puts "[fixtures:download] Downloading #{name}..."
    FileUtils.mkdir_p(target_dir)

    URI.open(url) do |remote|
      File.binwrite(zip_file, remote.read)
    end

    puts "[fixtures:download] Extracting #{name}..."
    Zip::File.open(zip_file) do |zip|
      zip.each do |entry|
        # Skip macOS metadata files and directories
        next if entry.name.start_with?("__MACOSX/") || entry.name.include?("/._")
        next if entry.directory?

        # Ensure entry.name is relative by stripping leading slashes
        relative_name = entry.name.sub(%r{^/+}, "")

        dest_path = File.join(target_dir, relative_name)
        FileUtils.mkdir_p(File.dirname(dest_path))

        # Skip if file already exists
        next if File.exist?(dest_path)

        # Write the file content directly
        File.binwrite(dest_path, entry.get_input_stream.read)
      end
    end

    FileUtils.rm(zip_file)
    puts "[fixtures:download] #{name} downloaded successfully"
  rescue LoadError => e
    warn "[fixtures:download] Error: Required gem not installed. Please run: gem install rubyzip"
    raise e
  end

  # Get font configurations from centralized source
  fonts = FixtureFonts.rakefile_config

  # Create file tasks for each font
  fonts.each do |name, config|
    file config[:marker] do
      if config[:single_file]
        download_single_file(name, config[:url], config[:marker])
      else
        download_font(name, config[:url], config[:target_dir])
      end
    end
  end

  desc "Download all test fixture fonts"
  task download: fonts.values.map { |config| config[:marker] }

  desc "Clean downloaded fixtures"
  task :clean do
    fonts.values.map { |config| config[:target_dir] }.each do |path|
      next unless File.exist?(path)

      puts "[fixtures:clean] Removing #{path}..."
      FileUtils.rm_rf(path)
      puts "[fixtures:clean] Removed #{path}"
    end
  end
end

# RSpec task depends on fixtures
RSpec::Core::RakeTask.new(spec: "fixtures:download")

# Default task runs spec and rubocop
task default: %i[spec rubocop]
