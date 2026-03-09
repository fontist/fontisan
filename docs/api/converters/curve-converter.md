---
title: CurveConverter
---

# CurveConverter

Convert between quadratic and cubic curves.

## Overview

`Fontisan::Converters::CurveConverter` handles Bézier curve conversion.

## Methods

### quadratic_to_cubic(points)

Convert quadratic points to cubic.

```ruby
converter = Fontisan::Converters::CurveConverter.new
cubic = converter.quadratic_to_cubic(quadratic_points)
```

### cubic_to_quadratic(points, tolerance: 0.5)

Convert cubic points to quadratic.

```ruby
quadratic = converter.cubic_to_quadratic(cubic_points, tolerance: 0.5)
```

## See Also

- [OutlineConverter](/api/converters/outline-converter)
