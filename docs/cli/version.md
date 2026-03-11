---
title: version
---

# version

Display the Fontisan version information.

## Usage

```bash
fontisan version
```

## Description

Shows the currently installed version of Fontisan. This is useful for:

- Verifying installation
- Checking compatibility
- Reporting issues with version information

## Examples

```bash
# Show version
fontisan version

# Output:
# fontisan 0.1.0
```

## Programmatic Access

You can also get the version programmatically:

```ruby
require 'fontisan'

puts Fontisan::VERSION
```

## Related Commands

- [info](/cli/info) — Get font information
- [tables](/cli/tables) — List font tables
