---
title: Engines
---

# Engines

The path-based operations of `Fontisan::Reference` (`read`, `outline_hashes`, `audit`, `audit_dir`, `scan`, `convert`, `extract`, `instance`, `glyph_ids`, `subset`) can run on one of three engine tiers. All tiers return the same results; they differ in speed.

| Tier | What it is |
|---|---|
| `ruby` | The pure Ruby implementation. Always available. |
| `native` | A compiled Rust extension (`Fontisan::Native`) loaded into the Ruby process. |
| `ffi` | A bundled Rust shared library (`Fontisan::Ffi`) called through the `ffi` gem, which is not a runtime dependency of fontisan. |

Reference timings on macOS arm64 (see `BENCHMARKS.md`, local run, not CI), native versus Ruby:

| Operation | Speedup |
|---|---|
| `audit` (one file) | 30x |
| `audit_dir` | 8.2x |
| `scan` (directory) | 3.9x |

Peak memory of a directory scan is about 4% lower on the native tier.

## Selecting an engine

Set `FONTISAN_ENGINE` before the process starts. Unset or empty means `auto`:

| Value | Behaviour |
|---|---|
| `ruby` | Use the Ruby tier only. |
| `native` | Use the native tier. |
| `ffi` | Use the ffi tier. |
| `auto` | The default. Currently serves everything from ruby; the Rust tiers are used only when selected explicitly, until the phase-3 gates pass (fontisan#160). After that, the first available tier in the order native, ffi, ruby. |

```sh
FONTISAN_ENGINE=native FONTISAN_ENGINE_STRICT=1 fontisan convert MyFont.ttf --to woff2 --output out.woff2
ruby -e 'require "fontisan"; p Fontisan::Reference.audit("MyFont.ttf").keys'
```

Any other value raises `Fontisan::Engine::ConfigError`.

### Command line

The same variables apply to the CLI, but only for the commands that go through the engine: `convert`, `unpack`, `subset` and `instance`. Each routes only its plain cases: `convert` a single-target conversion (several targets, instance coordinates, conversion options, hinting, a collection target format, compression options or a font index run on Ruby); `subset` by `--text` or `--unicode` with the `pdf`, `web` or `minimal` profile; `instance` of a TrueType variable font by axis coordinates to the same format (`--to`, `--named-instance` and `--list-instances` run on Ruby). Every other command (`info`, `validate`, `export`, `pack`, and so on) runs on Ruby.

## Strict mode

If a forced tier (`native` or `ffi`) is not available, fontisan falls back to Ruby silently. Set `FONTISAN_ENGINE_STRICT=1` (also `true`, `yes`, `on`; `0`, `false`, `no`, `off` leave it off, anything else raises `Fontisan::Engine::ConfigError`) to raise `Fontisan::Engine::TierUnavailable` instead:

```sh
FONTISAN_ENGINE=native FONTISAN_ENGINE_STRICT=1 ruby -rfontisan -e 'Fontisan::Reference.audit("MyFont.ttf")'
```

Strict mode does not apply to operations a tier cannot serve (see below); those always go to Ruby.

## Which tier served a call

`Fontisan::Engine.served_by(operation)` returns the tier (a Symbol) that served the last call of that operation in the current process, or `nil` if there was none.

```ruby
ENV["FONTISAN_ENGINE"] = "auto"
Fontisan::Reference.audit("MyFont.ttf")
Fontisan::Engine.served_by(:audit)   # => :native
```

`Fontisan::Engine.scan(paths)` and `Fontisan::Engine.audit_dir(dir)` return the same rows as the `Reference` methods with an added `"served_by"` key per row or entry. Results of the `Reference` methods themselves do not change with the tier.

## What stays on Ruby

These always run on the Ruby tier, whichever engine is selected, and strict mode does not raise for them:

- The object-based API: `Fontisan::Subset::Builder.new(font, ...)` and `Fontisan::Variable::Instancer`. Only the path-based `Reference.subset` and `Reference.instance` can use another tier.
- Apple dfont files.
- CLI commands other than `convert`, `unpack` and `subset`, and the non-plain `convert` cases listed above.
- Type 1 fonts (PFB/PFA).

## Platforms

Platform gems with the native extension and the bundled shared library are published for:

- `x86_64-linux`
- `x86_64-linux-musl`
- `arm64-darwin`
- `x86_64-darwin`
- `x64-mingw-ucrt` (Ruby 3.2 to 4.0)

The `java` gem (JRuby) carries the shared library only (bundled for linux-x86_64, darwin-arm64, darwin-x86_64 and windows-x86_64; no musl or linux-arm64), so it serves the `ffi` tier. It depends on neither `brotli` nor `rb_sys`; a WOFF2 operation that falls to the Ruby tier on this gem raises `Fontisan::Engine::Woff2Unavailable`.

The plain source gem builds the native extension at install time when a Rust toolchain (`cargo`) and the `rb_sys` gem are present. Without them the install still succeeds and fontisan runs on the Ruby tier.

## Troubleshooting

### "native tier not available"

With `FONTISAN_ENGINE=native` and `FONTISAN_ENGINE_STRICT=1` you get `TierUnavailable`: the native extension did not load. Check:

```sh
ruby -rfontisan -e 'p Fontisan::Native.available?, Fontisan::Ffi.available?'
```

- `false` on an installed platform gem: the gem was installed on a Ruby version or platform it does not cover. Run `gem list fontisan` and check the platform suffix; install the matching one.
- `false` on a source install: the extension was skipped because `cargo` or `rb_sys` was missing. See below.
- Without strict mode, the same condition silently serves from Ruby; use `Fontisan::Engine.served_by` to confirm which tier ran.

For the ffi tier, `FONTISAN_CDYLIB` can point at a specific shared library file.

### Building from source

Install a Rust toolchain ([rustup](https://rustup.rs)), then reinstall so the extension is compiled:

```sh
gem install rb_sys
gem install fontisan --platform ruby
```

With Bundler, add `gem "fontisan", force_ruby_platform: true` to build from the source gem. Set `FONTISAN_NATIVE_REQUIRED=1` during the install to make a missing toolchain or a failed build an error instead of a silent skip. `FONTISAN_SKIP_CDYLIB=1` skips building the shared library for the ffi tier.
