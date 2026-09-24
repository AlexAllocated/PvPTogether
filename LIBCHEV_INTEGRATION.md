# libchev integration — September 24, 2026

PvPTogether vendors **libchev 1.1.0** at immutable commit [`1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6`](https://github.com/AlexAllocated/libchev/commit/1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6). `Libs/libchev/manifest.json` records SHA-256 hashes for each embedded source/license file. The upstream vendor tool verified the provisional embed against its historical Git revision before migrating it. Embedded source was not edited locally.

Each addon loader gets its own `namespace.LibChev`. PvPTogether captures that private instance; there is no global registry or provisional `Together` alias. Nameplate classification, native permissions, restriction checks, journal ownership, and lifecycle decisions remain in PvPTogether. The shared debug controller owns bounded log storage operations, category/search state, diagnostic export history, test presentation, debug-command dispatch, and the complete console. PvPTogether supplies private stores, its domain report/tests, and restriction callbacks; it also uses shared weak-table construction and generation fencing.

## User-visible behavior

- `/pt debug` and `/pt dump` open the common console. All consumers use the same category popup, fuzzy/quoted search, tail-following scroll behavior, copy/clear controls, and test/diagnostics/log/reload buttons. `/pt dump CATEGORY` selects a category; `/pt dump clear` clears history without resetting nameplate counters.

- `/pt diagnostics` opens a copyable report with common addon/library/client headers, existing capability/settings/pending-work details, bounded counters, and sampled static reasons. The first three occurrences and every hundredth occurrence of a reason are sampled. History is bounded to 60 entries of at most 100 characters each.
- Restricted or unavailable report UI falls back to chat. Region mutation requires both the library's owned-region checks and PvPTogether's native permission checks. Callbacks recheck restrictions; window-construction failures are contained without printing the foreign exception.
- `/pt test` runs **15 detached checks**: 13 shared self-tests plus 2 addon checks. It does not replace engine APIs, create nameplates, reset runtime stores, or modify saved settings. Failure output contains static test labels and a summary, not raw foreign error payloads. The standalone offline runner executes these same bodies too. The slash command replaces TEST history and presents current results in the shared console, with chat fallback under the same guards as general diagnostics. Programmatic `RunTests()` remains headless by default; `RunTests(true)` explicitly requests presentation.

The addon version is **1.1.0-beta.2**, with [release notes](CHANGELOG.md). Publication uses the existing annotated-tag convention and a GitHub prerelease. The prior [Retail/Forever audit](AUDIT_2026-09-24.md) and its live-validation limits still apply.

## Validation

- **141/141 offline tests**, normal and reverse order, under both actual **Lua 5.1.5** and **Lua 5.2.4**.
- All **14 Lua files** parse under both interpreters; StyLua and diff whitespace checks pass.
- TOC order resolves all nine runtime files; offline runners/engine fixtures remain excluded.
- Upstream `scripts/vendor.py --check` validates the exact embedded revision and hashes.
- Integration tests exercise the actual 15 live-check bodies and headless runner, no live-state mutation from headless execution, shared command and button behavior, private copies in both addon load orders, report creation/reuse, native-permission rejection, restriction transitions, chat fallback, error-payload suppression, and bounded reason sampling. Existing Retail and Forever geometry/lifecycle regressions continue to pass.

These are offline checks. No real-client report copy/paste, `/pt test`, combat, visual, or taint session was performed for this extraction. The existing Retail and Forever symlinks still resolve to this checkout, so the next UI load uses it. No saved variables or client configuration files were edited.

## Next client checks

Reload Retail and Forever, run `/pt test` (expect 15 passed), then `/pt diagnostics`. Verify the report can be selected/copied, scrolled, closed, and reopened. During restrictions, diagnostics should fall back to chat; callbacks from an already-open report should stop until restrictions end. Repeat the prior audit's combat, recycled-plate, settings, disable/re-enable, and multi-addon checks. Report the client build, copied diagnostics, and the first error/blocked-action stack separately if a failure occurs.

For future library updates, use the upstream vendor script with an exact reviewed commit, then repeat consumer validation. Never hand-edit files under `Libs/libchev`.
