# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "fileutils"

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :fixtures do
  fixtures_dir = "spec/fixtures/fonts"

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
        dest_path = File.join(target_dir, entry.name)
        FileUtils.mkdir_p(File.dirname(dest_path))
        entry.extract(dest_path) unless File.exist?(dest_path)
      end
    end

    FileUtils.rm(zip_file)
    puts "[fixtures:download] #{name} downloaded successfully"
  rescue LoadError => e
    warn "[fixtures:download] Error: Required gem not installed. Please run: gem install rubyzip"
    raise e
  end

  # Font configurations with target directories and marker files
  # All fonts are downloaded via Rake
  fonts = {
    "NotoSans" => {
      url: "https://github.com/notofonts/notofonts.github.io/raw/refs/heads/main/fonts/NotoSans/full/ttf/NotoSans-Regular.ttf",
      target_dir: fixtures_dir.to_s,
      marker: "#{fixtures_dir}/NotoSans-Regular.ttf",
      single_file: true,
    },
    "Libertinus" => {
      url: "https://github.com/alerque/libertinus/releases/download/v7.051/Libertinus-7.051.zip",
      target_dir: "#{fixtures_dir}/libertinus",
      marker: "#{fixtures_dir}/libertinus/Libertinus-7.051/static/OTF/LibertinusSerif-Regular.otf",
    },
    "MonaSans" => {
      url: "https://github.com/github/mona-sans/releases/download/v2.0/MonaSans.zip",
      target_dir: "#{fixtures_dir}/MonaSans",
      marker: "#{fixtures_dir}/MonaSans/MonaSans/variable/MonaSans[wdth,wght].ttf",
    },
    "NotoSerifCJK" => {
      url: "https://github.com/notofonts/noto-cjk/releases/download/Serif2.003/01_NotoSerifCJK.ttc.zip",
      target_dir: "#{fixtures_dir}/NotoSerifCJK",
      marker: "#{fixtures_dir}/NotoSerifCJK/NotoSerifCJK.ttc",
    },
    "NotoSerifCJK-VF" => {
      url: "https://github.com/notofonts/noto-cjk/releases/download/Serif2.003/02_NotoSerifCJK-OTF-VF.zip",
      target_dir: "#{fixtures_dir}/NotoSerifCJK-VF",
      marker: "#{fixtures_dir}/NotoSerifCJK-VF/Variable/OTC/NotoSerifCJK-VF.otf.ttc",
    },
  }

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
    %w[libertinus MonaSans NotoSerifCJK NotoSerifCJK-VF
       NotoSans-Regular.ttf].each do |dir|
      path = File.join(fixtures_dir, dir)
      if File.exist?(path)
        FileUtils.rm_rf(path)
        puts "[fixtures:clean] Removed #{path}"
      end
    end
  end
end

# RSpec task depends on fixtures
RSpec::Core::RakeTask.new(spec: "fixtures:download")

# Default task runs spec and rubocop
task default: %i[spec rubocop]
