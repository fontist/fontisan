---
layout: home
pageClass: my-index-page

hero:
  name: "Fontisan"
  text: "Universal font processing library for Ruby"
  tagline: The most comprehensive font library — 100% Pure Ruby, no Python, no C++, no C# dependencies.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/
    - theme: alt
      text: View on GitHub
      link: https://github.com/fontist/fontisan
    - theme: alt
      text: Migrate from fonttools
      link: /guide/migrations/fonttools

features:
  - title: "🔄 Font Conversion"
    details: Convert between TTF, OTF, WOFF, WOFF2, Type 1 (PFB/PFA), and SVG formats with curve conversion and optimization.
  - title: "✅ Font Validation"
    details: Comprehensive validation with 5 profiles (OpenType, Google Fonts, Microsoft, Adobe, Production), 56 helpers, and custom DSL.
  - title: "🎨 Color Fonts"
    details: Full support for COLR/CPAL layered color fonts, sbix bitmap fonts, and SVG-based color fonts.
  - title: "⚡ Variable Fonts"
    details: Process OpenType variable fonts with instance generation, format conversion, and named instance support.
  - title: "🔧 Font Hinting"
    details: Bidirectional hint conversion between TrueType and PostScript formats — a unique Fontisan capability.
  - title: "📦 Type 1 Support"
    details: Adobe Type 1 fonts (PFB/PFA) with eexec decryption, CharString parsing, and conversion to modern formats.
  - title: "📚 Collections"
    details: TTC/OTC/dfont collection support with pack, unpack, table deduplication, and format conversion.
  - title: "💎 Pure Ruby"
    details: Zero external dependencies. No Python, no C++, no C# required. Works anywhere Ruby runs.
---

<WithinHero>
<HeroCodeBlock title="fontisan"><div class="line"><span class="comment"># Get detailed font information</span></div><div class="line"><span class="prompt">$</span> <span class="cmd">fontisan</span> info OpenSans-Regular.ttf</div><div class="line">Family: Open Sans    Style: Regular    Format: TTF</div><div class="line"><span class="comment"># Convert between formats</span></div><div class="line"><span class="prompt">$</span> <span class="cmd">fontisan</span> convert font.ttf --to woff2</div><div class="line"><span class="success">✓</span> font.woff2 created (45% smaller)</div><div class="line"><span class="comment"># Validate with Google Fonts profile</span></div><div class="line"><span class="prompt">$</span> <span class="cmd">fontisan</span> validate font.ttf -p google_fonts</div><div class="line"><span class="success">✓</span> All 56 checks passed</div></HeroCodeBlock>
</WithinHero>

<style>
.pure-ruby-hero {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.25rem 0.75rem;
  background: linear-gradient(135deg, #bf4e6a, #d4718a);
  color: white;
  border-radius: 9999px;
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-top: 1rem;
}
</style>

<div class="pure-ruby-hero">
  💎 100% Pure Ruby
</div>

## Why Fontisan?

Fontisan is the **most comprehensive font processing library in pure Ruby**, combining the capabilities of:

- **fonttools** (Python) — 100+ OpenType tables, variable fonts, subsetting
- **lcdf-typetools** (C++) — otfinfo, cfftot1, Type 1 validation
- **Font-Validator** (C#) — Comprehensive validation with coverage reports

**The key differentiator**: Fontisan is 100% pure Ruby. No Python, no C++, no C# dependencies. Install and run anywhere Ruby runs.

## Feature Comparison

| Feature | fonttools | lcdf-typetools | Font-Validator | **Fontisan** |
|---------|-----------|----------------|----------------|--------------|
| Pure Ruby | ❌ | ❌ | ❌ | ✅ |
| Python-free | ❌ | ✅ | ✅ | ✅ |
| Font conversion | ✅ | ✅ | ❌ | ✅ |
| Validation | ❌ | ❌ | ✅ | ✅ |
| Bidirectional hints | ❌ | Partial | ❌ | ✅ |
| Variable fonts | ✅ | ❌ | ❌ | ✅ |
| Type 1 support | Partial | ✅ | ❌ | ✅ |

[See full comparison →](/guide/comparisons/)

## CLI Usage

```bash
# Get font information
fontisan info font.ttf

# Convert fonts
fontisan convert input.ttf --to otf --output output.otf

# Validate fonts
fontisan validate font.ttf --profile google_fonts

# Work with collections
fontisan unpack fonts.ttc --output-dir ./extracted
```

## Ruby API

```ruby
require 'fontisan'

# Load any font format
font = Fontisan::FontLoader.load('font.ttf')

# Get font information
info = Fontisan::Commands::InfoCommand.new(font: font).run
puts info.family_name
puts info.style

# Convert between formats
Fontisan::FontWriter.write(font, 'output.woff2')

# Validate a font
result = Fontisan::FontValidator.validate('font.otf', profile: :google_fonts)
puts result.passed?
```

## Migration Guides

Coming from another tool? We have migration guides:

- [From fonttools (Python)](/guide/migrations/fonttools) — Comprehensive Python to Ruby migration
- [From extract_ttc](/guide/migrations/extract-ttc) — Already fully compatible
- [From otfinfo](/guide/migrations/otfinfo) — Command equivalents for lcdf-typetools
- [From Font-Validator](/guide/migrations/font-validator) — Validation profile mapping

## License

Fontisan is open source and available under the [MIT License](https://github.com/fontist/fontisan/blob/main/LICENSE).
