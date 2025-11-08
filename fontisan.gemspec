# frozen_string_literal: true

require_relative "lib/fontisan/version"

Gem::Specification.new do |spec|
  spec.name = "fontisan"
  spec.version = Fontisan::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Font analysis tools and utilities for OpenType fonts"
  spec.description = <<~HEREDOC
    Fontisan provides font analysis tools and utilities. It is
    designed as a pure Ruby implementation with full object-oriented architecture,
    supporting extraction of information from OpenType and TrueType fonts (OTF, TTF, OTC, TTC).

    The gem provides both a Ruby library API and a command-line interface,
    with structured output formats (YAML, JSON, text).
  HEREDOC

  spec.homepage = "https://github.com/fontist/fontisan"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/fontist/fontisan"
  spec.metadata["changelog_uri"] = "https://github.com/fontist/fontisan/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bindata", "~> 2.5"
  spec.add_dependency "lutaml-model", "~> 0.7"
  spec.add_dependency "thor", "~> 1.4"
end
