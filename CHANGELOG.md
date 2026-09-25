# Changelog

## 1.2.1 — 2026-09-24

Show Blizzard's crossed-swords icon beside PvPTogether in the AddOns list instead of the default question mark.

## 1.2.0 — 2026-09-24

Declare current Classic client support and add six-client checks for category borders, native settings and cleanup. Keep Blizzard in control of native styles; all clients use the same guarded border implementation.

Validation: 117 tests pass in both orders on Lua 5.1 and 5.2, with six client profiles, Lua parsing and exact private-library vendor checks. NoPoizen client smoke checks and package verification also pass. Live validation of the new adapters remains pending.

See [CLIENT_COMPATIBILITY.md](CLIENT_COMPATIBILITY.md) for source evidence, scope and validation limits.

## 1.1.1 — 2026-09-24

Keep overlapping debug consoles and their controls in one native stacking group through private libchev 1.1.3. Category menus stay with their owning console.

- Retire per-category style overrides and previews. Blizzard's global nameplate settings now own all native layout and style behavior.
- Keep party, friendly-player, and enemy-player border toggles and colors. Add a **Blizzard Nameplate Settings** button to `/pt`.
- Remove native geometry mutations, snapshot observers, restoration journals, and style reapplication hooks. Borders use only addon-owned textures and retain guarded identity, recycling, cleanup, and deferred refresh behavior.
- Preserve old saved style preferences as ignored data; no saved files are rewritten externally. `/reload` clears the previous runtime's geometry overrides.
- Report native layout ownership and border refresh/cleanup status in `/pt diagnostics`.

Validation: 111 offline regressions pass in both orders on Lua 5.1 and 5.2. Native frame fixtures reject all widget mutations except creating addon-owned textures. Coverage includes unreadable native geometry, native layout changes, restrictions, pooled frames, stale callbacks, disable/re-enable, and the Settings shortcut. Updated UI and gameplay behavior still require live Retail/Forever validation.

## 1.1.0 — 2026-09-24

Use the same private libchev 1.1.2 debug console across all three addons, including category/search filters, copy controls, test results, diagnostic reports, timestamps when available, and a single final test summary. Fix stretched native frame artwork with explicit texture bounds.

Includes Retail/Forever nameplate lifecycle hardening, home-party-only styling, guarded cleanup, and a safe clock adapter for consistent timestamped diagnostics. Run `/pt test`, `/pt debug`, or `/pt diagnostics`. In-game tests use 15 detached checks; offline engine fixtures remain excluded.

Validation: 144 offline regressions pass in both orders on Lua 5.1/5.2. The user confirmed the corrected shared frame appearance in-game. Earlier Forever build 70009 results were 15/15; this is not a blanket claim about every live restriction or gameplay path.

## 1.1.0-beta.3 — 2026-09-24

- Update the shared libchev console to native WoW dialog artwork and button textures while retaining addon-owned frames and restriction guards.
- Show one test summary per run.
- Supply a safe clock to the shared log formatter so events include timestamps and sequence numbers consistently. Unavailable, secret, or nonfinite clock values are omitted.
- Keep detached self-tests independent of the native clock. Audit confirms the TOC-loaded tests contain no undefined arithmetic or generated NaN fixtures.

Validation: 144 offline regressions pass in both orders under Lua 5.1.5 and 5.2.4. The user reported all 15 in-game checks passing on Forever 1.60.1 build 70009 with beta.2; beta.3 artwork and gameplay/taint behavior still require live validation. Reload and run `/pt test`, then check `/pt debug` and `/pt diagnostics`.

## 1.1.0-beta.2 — 2026-09-24

- Use libchev 1.1.0's shared debug controller and console. Logging, filters, search, scrolling, test presentation, and debug commands now use the same implementation across consumers.
- Fix `/pt test` to open current test results in that console, including addon/library headers, suite purpose, summary, and static failure labels. Previous TEST results are replaced each run.
- Add `/pt debug`, `/pt dump`, `/pt dump CATEGORY`, and `/pt dump clear`, plus console controls for tests, diagnostics, copying, clearing, and reloading.
- Preserve chat fallback when UI is restricted or unavailable, detached programmatic tests, bounded static-reason history, and the policy excluding raw foreign errors and unit identity.

Validation: 141 offline regressions pass in normal and reverse order under Lua 5.1.5 and 5.2.4. The exact embedded revision is `1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6`. Runtime ZIP contents and vendor hashes are verified.

Real Retail/Forever window interaction, combat, and taint behavior remain unverified. Reload and run `/pt test` to see 15 passed, then `/pt diagnostics` to switch to the addon report. Use `/pt debug` to return to event history.

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
