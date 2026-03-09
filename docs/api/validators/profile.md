---
title: ValidationProfile
---

# ValidationProfile

Validation profile definitions.

## Overview

`Fontisan::Validators::ValidationProfile` defines validation profiles.

## Built-in Profiles

| Profile | Checks | Use Case |
|---------|--------|----------|
| `indexability` | 8 | Font discovery |
| `usability` | 26 | Installation |
| `production` | 37 | Quality assurance |
| `web` | 18 | Web deployment |
| `spec_compliance` | Full | Spec audit |

## Methods

### checks

Get list of checks in profile.

```ruby
profile = Fontisan::Validators::ValidationProfile[:production]
profile.checks.each do |check|
  puts check.id
end
```

## See Also

- [FontValidator](/api/validators/font-validator)
- [Validation Helpers](/guide/validation/helpers)
