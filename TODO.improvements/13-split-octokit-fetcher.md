# 13 — Split `OctokitFetcher` out of `fixture_downloader.rb`

## Priority
P3

## Problem

`spec/support/fixture_downloader.rb` (post-PR #111) is ~350 lines with two distinct concerns:

1. **Retry / routing loop** (the `Downloader` class) — backoff, Retry-After, permanent-vs-transient classification.
2. **Octokit URL dispatch** (the `OctokitFetcher` module) — release-asset, raw-file, contents-API routing.

These are MECE-distinct. Bundling them in one file muddies the boundary; future changes to Octokit routing shouldn't require reading the retry loop.

## Goal

`OctokitFetcher` moves to its own file `spec/support/fixture_downloader/octokit_fetcher.rb`. The `Downloader` class becomes the only public surface in `spec/support/fixture_downloader.rb` and delegates to `OctokitFetcher` when needed.

## Approach

1. Create `spec/support/fixture_downloader/` directory.
2. Move `OctokitFetcher` module to `spec/support/fixture_downloader/octokit_fetcher.rb`.
3. Move `HttpStatusIo` and `Downloader` constants stay in `spec/support/fixture_downloader.rb`.
4. Add a `module FixtureFonts::Downloader` autoload or simple `require_relative "fixture_downloader/octokit_fetcher"` from `fixture_downloader.rb`.

Actually — for spec/support files, `require_relative` is acceptable (CLAUDE.md rule on autoload is for `lib/`). No autoload needed; the Rakefile's `require_relative` chain handles loading.

## Out of scope

- Splitting the Downloader further — it's cohesive.
- Moving `fixture_downloader_spec.rb` — already sibling, fine where it is.

## Effort

~1 hour.

## Dependencies

None.

## Acceptance criteria

- `spec/support/fixture_downloader.rb` < 200 lines.
- `spec/support/fixture_downloader/octokit_fetcher.rb` exists and contains all Octokit-specific code.
- All existing specs pass unchanged.
