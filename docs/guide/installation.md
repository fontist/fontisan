---
title: Installation
---

# Installation

## Requirements

- Ruby 3.0 or higher
- No external dependencies (pure Ruby)

## Installing the Gem

### With Bundler

Add this line to your application's Gemfile:

```ruby
gem 'fontisan'
```

And then execute:

```bash
bundle install
```

### Manual Installation

Install it yourself as:

```bash
gem install fontisan
```

## Verifying Installation

```bash
# Check if CLI is available
fontisan --version

# Get help
fontisan --help
```

## Installing from Source

For development or to use the latest features:

```bash
git clone https://github.com/fontist/fontisan.git
cd fontisan
bundle install
bundle exec rake install
```

## Dependencies

Fontisan is **100% pure Ruby** with no external dependencies:

- No Python required
- No C++ compilation needed
- No native extensions
- Works on Linux, macOS, Windows, and BSD

### Optional Dependencies

For development:

```bash
# Install development dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop
```

## Troubleshooting

### Ruby Version

Fontisan requires Ruby 3.0 or higher. Check your version:

```bash
ruby --version
```

### Permission Issues

If you encounter permission errors, try:

```bash
# Install to user directory
gem install fontisan --user-install

# Or use sudo (not recommended)
sudo gem install fontisan
```

### Bundler Issues

If Bundler has issues:

```bash
# Update Bundler
gem update bundler

# Clear cache
bundle clean --force

# Reinstall
bundle install --redownload
```
