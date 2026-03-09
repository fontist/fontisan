---
title: FontValidator
---

# FontValidator

Main validation entry point.

## Overview

`Fontisan::Validators::FontValidator` validates fonts against profiles.

## Class Methods

### validate(path, profile: :production)

Validate a font file.

```ruby
result = Fontisan::Validators::FontValidator.validate('font.ttf', profile: :web)
if result.valid?
  puts "Font is valid"
else
  puts "Errors: #{result.errors.length}"
end
```

## See Also

- [Validation Guide](/guide/validation/)
- [ValidationProfile](/api/validators/profile)
