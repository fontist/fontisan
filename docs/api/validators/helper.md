---
title: ValidationHelper
---

# ValidationHelper

Individual validation helpers.

## Overview

Validation helpers perform specific checks.

## Categories

| Category | Helpers | Focus |
|----------|---------|-------|
| Table | 12 | Table structure |
| Name | 8 | Name records |
| Head | 6 | Header validation |
| Metrics | 10 | Font metrics |
| Glyph | 8 | Glyph data |
| CMAP | 6 | Character mapping |
| Layout | 6 | GSUB/GPOS |

## Using Helpers

```ruby
validator = Fontisan::Validators::FontValidator.new(font)
result = validator.check_required_tables
puts result.valid?
```

## See Also

- [FontValidator](/api/validators/font-validator)
- [Validation Helpers Guide](/guide/validation/helpers)
