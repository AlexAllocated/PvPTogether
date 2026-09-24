# Changelog

## 1.1.0-beta.1 — 2026-09-24

- Support current Retail and Forever nameplate layouts, including modern cast-bar containers.
- Harden native mutation permissions, recycled-frame identity, deferred work, and reversible cleanup when settings change or the addon is disabled.
- Preserve native nameplate layout updates and third-party styling changes.
- Add a copyable `/pt diagnostics` report with bounded static-reason history and restricted-state chat fallback.
- Add `/pt test`: 12 detached self-checks without loading offline engine fixtures or changing live settings.
- Embed a private copy of libchev 1.0.0 at commit `09ac76eb6fe8e9589b809188652950c3cd9e444c`; diagnostics and test output omit raw foreign errors and unit identity.

Validation: 129 offline tests pass in both execution orders under Lua 5.1.5 and 5.2.4. Syntax, formatting, vendor hashes, and TOC checks pass.

This is a prerelease. Actual Retail/Forever visuals, combat and taint behavior, and report copy/paste still require client validation. After reloading, run `/pt test` (expect 12 passed) and `/pt diagnostics`, then exercise recycled nameplates, settings, and disable/re-enable in and out of restrictions. Offline success does not establish live-client safety.

Classic geometry and native name-color, selection, click-area, and stacking behavior remain global. See the audit and compatibility documents in the repository for details.
