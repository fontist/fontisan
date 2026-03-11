---
title: Contributing Guide
---

# Contributing Guide

Thank you for your interest in contributing to Fontisan! This guide covers how to set up your development environment and run tests.

## Development Setup

### Prerequisites

- Ruby 3.0 or higher
- Bundler gem
- Git

### Clone and Setup

```bash
# Clone the repository
git clone https://github.com/fontist/fontisan.git
cd fontisan

# Install dependencies
bundle install

# Verify installation
bundle exec fontisan version
```

## Running Tests

### Full Test Suite

```bash
# Run all tests
bundle exec rspec

# Run with documentation format
bundle exec rspec --format documentation

# Run with progress format (default)
bundle exec rspec --format progress
```

### Running Specific Tests

```bash
# Run specific file
bundle exec rspec spec/fontisan/tables/maxp_spec.rb

# Run specific test by line number
bundle exec rspec spec/fontisan/tables/maxp_spec.rb:42

# Run all table tests
bundle exec rspec spec/fontisan/tables/

# Run all CLI tests
bundle exec rspec spec/fontisan/cli/
```

### Running Tests by Tag

```bash
# Run only unit tests
bundle exec rspec --tag ~integration

# Run only integration tests
bundle exec rspec --tag integration

# Run only slow tests
bundle exec rspec --tag slow
```

## Test Fixtures

Fontisan uses a centralized fixture configuration system for test fonts.

### Automatic Fixture Download

Test fixtures are automatically downloaded before tests run:

```bash
# Run tests (fixtures download automatically)
bundle exec rspec

# Manual fixture management
bundle exec rake fixtures:download  # Download all test fonts
bundle exec rake fixtures:clean     # Remove downloaded fonts
bundle exec rake fixtures:list      # List all fixtures
```

### Fixture Locations

Fixtures are stored in `spec/fixtures/`:

```
spec/fixtures/
├── fonts/
│   ├── libertinus/        # Libertinus Serif test fonts
│   ├── MonaSans/          # Mona Sans variable fonts
│   └── NotoSerifCJK/      # CJK collection fonts
└── expected/               # Expected output files
```

### Adding New Fixtures

1. Add fixture URL to `spec/fixtures/fixtures.yml`
2. Run `bundle exec rake fixtures:download`
3. Reference in your tests

```ruby
# Example test using fixture
RSpec.describe Fontisan::Tables::Maxp do
  let(:font_path) { 'spec/fixtures/fonts/libertinus/ttf/LibertinusSerif-Regular.ttf' }

  it 'reads maxp table' do
    font = Fontisan::FontLoader.load(font_path)
    expect(font.table('maxp').num_glyphs).to eq(2731)
  end
end
```

## Test Organization

### Directory Structure

```
spec/
├── spec_helper.rb           # Test configuration
├── fixtures/                # Test font files
├── fontisan/
│   ├── cli/                 # CLI command tests
│   ├── tables/              # OpenType table tests
│   ├── converters/          # Converter tests
│   ├── validators/          # Validator tests
│   └── fontisan_spec.rb     # Main module tests
└── support/                 # Test helpers and matchers
```

### Test Categories

| Category | Location | Description |
|----------|----------|-------------|
| Unit | `spec/fontisan/` | Individual component tests |
| Integration | `spec/integration/` | End-to-end workflow tests |
| CLI | `spec/fontisan/cli/` | Command-line interface tests |

## Writing Tests

### Basic Test Structure

```ruby
require 'spec_helper'

RSpec.describe Fontisan::Tables::Head do
  let(:font) { Fontisan::FontLoader.load(fixture_path) }
  let(:head_table) { font.table('head') }

  describe '#units_per_em' do
    it 'returns the units per em value' do
      expect(head_table.units_per_em).to eq(1000)
    end
  end

  describe '#valid_magic?' do
    it 'validates the magic number' do
      expect(head_table.valid_magic?).to be true
    end
  end
end
```

### Testing CLI Commands

```ruby
require 'spec_helper'

RSpec.describe 'fontisan info' do
  it 'displays font information' do
    output = `bundle exec fontisan info #{fixture_path}`

    expect(output).to include('Family:')
    expect(output).to include('Style:')
  end
end
```

### Custom Matchers

Fontisan provides custom RSpec matchers:

```ruby
# Check if output is valid font
expect(output_font).to be_valid_font

# Check if font has table
expect(font).to have_table('head')

# Check if font is valid TrueType
expect(font).to be_truetype_font
```

## Debugging Tests

### Verbose Output

```bash
# Run with verbose output
bundle exec rspec --format documentation

# Run with backtraces
bundle exec rspec --backtrace
```

### Debugging Single Test

```ruby
# Add to test for debugging
it 'debugs something' do
  require 'pry'; binding.pry
  # Test code here
end
```

## Continuous Integration

Tests run automatically on GitHub Actions for:

- Ruby 3.0, 3.1, 3.2, 3.3
- Ubuntu, macOS, Windows

### CI Configuration

See `.github/workflows/rake.yml` for CI configuration.

## Code Quality

### Linting

```bash
# Run RuboCop
bundle exec rubocop

# Auto-correct issues
bundle exec rubocop -a
```

### Documentation

```bash
# Generate YARD documentation
bundle exec yard doc
```

## Reporting Issues

When reporting issues, please include:

1. Ruby version (`ruby -v`)
2. Fontisan version (`fontisan version`)
3. Sample font file (if possible)
4. Command that failed
5. Expected vs actual behavior

## Pull Requests

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit pull request

### PR Checklist

- [ ] Tests pass (`bundle exec rspec`)
- [ ] Code passes linting (`bundle exec rubocop`)
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG updated (if applicable)
