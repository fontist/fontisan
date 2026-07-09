# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in fontisan.gemspec
gemspec

gem "benchmark"
# bigdecimal is required by get_process_mem for Ruby 3.4+ compatibility
gem "bigdecimal"
gem "canon", "~> 0.1.3"
gem "get_process_mem", "~> 0.2"
# Octokit provides authenticated GitHub API access for the test-only
# fixture downloader (spec/support/fixture_downloader.rb). CI sets
# GITHUB_TOKEN, the downloader auto-detects it and routes GitHub URLs
# through Octokit to lift the 60/hr anonymous rate limit. NOT in
# fontisan.gemspec — production installs never pull this in.
gem "octokit", group: :test
gem "openssl", "~> 3.0"
gem "rake"
gem "rspec"
gem "rubocop"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "rubyzip"
# sys-proctable is required by get_process_mem on Windows
gem "sys-proctable", platforms: %i[mswin mingw mswin64]
# win32ole was a default gem until Ruby 4.0 — pin it for Windows runners
gem "win32ole", platforms: %i[mswin mingw mswin64]
