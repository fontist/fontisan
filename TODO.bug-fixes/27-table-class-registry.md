# 27 — Table class registry (OCP: eliminate case/when tag dispatch)

## Priority
P2

## Problem
The codebase has 8+ `case tag` dispatches that map a string tag like
`"HVAR"` to a Ruby class like `Tables::Hvar`. Each new table requires
updating every dispatch site. This violates OCP and DRY.

## Sites
- `lib/fontisan/variable/delta_applicator.rb:269` — case tag → table class
- `lib/fontisan/variable/static_font_builder.rb:91` — case tag → update method
- `lib/fontisan/variable/static_font_builder.rb:185` — case tag → table class
- `lib/fontisan/woff2/table_transformer.rb:36` — case tag → transform strategy
- `lib/fontisan/woff2/table_transformer.rb:62` — case tag → inverse transform
- `lib/fontisan/export/ttx_generator.rb:100` — case tag → transformer
- `lib/fontisan/variation/metrics_adjuster.rb:221` — case tag → metric
- `lib/fontisan/variation/instance_writer.rb:259` — case tag → writer

## Approach
Create `Tables::Registry` as a single source of truth for tag → class.
Each table file registers itself via a `register_tag` call:

```ruby
# lib/fontisan/tables/hvar.rb
module Fontisan
  module Tables
    class Hvar < Binary::BaseRecord
      register_tag "HVAR"
      ...
    end
  end
end
```

`Tables::Registry.for(tag)` returns the class. Dispatch sites become:

```ruby
table_class = Tables::Registry.for(tag)
return nil unless table_class
```

This is OCP-compliant: adding a new table means adding `register_tag`
in the table's file, not modifying dispatch sites.

## Acceptance criteria
- 0 `case tag` dispatches in `lib/fontisan/`
- All callers use `Tables::Registry.for(tag)` instead
- All existing specs pass
