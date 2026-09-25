# Offline regressions

The historical style-reset probe is preserved at commit `86aea5d`; see [STYLE_OVERRIDE_REVIEW.md](../STYLE_OVERRIDE_REVIEW.md) for reproduction instructions. It applies to the retired implementation, not the current addon.

Run from the repository root with a standalone Lua interpreter:

```sh
lua scripts/test.lua
lua scripts/test.lua . reverse
```

The runner also accepts an absolute repository path as its first argument. Each case loads production Lua into a fresh private environment with an independent database, event dispatcher, timer queue, API fixtures, and frames. No offline runner or fixture file is loaded by the addon manifest. The separate `/pt test` command runs only the thirteen detached library self-tests and two pure addon checks from `InGameTests.lua`. The offline suite also registers those exact fifteen bodies and verifies that running the headless `RunTests()` entry point does not alter addon settings, diagnostics, frame state, hooks, or timers. The `/pt test` slash command explicitly requests presentation in the shared guarded debug console. Separate regressions cover current result headers/summary, window creation/reuse, stale failure replacement, and safe chat fallback when UI is restricted, missing, or throws. Shared command and button tests also verify category selection, search reset, history clearing without resetting domain counters, report/log switching, and guarded reload callbacks. Clock regressions cover shared elapsed/sequence formatting, inaccessible or nonfinite clock rejection, and detached live-test bodies that never query the native clock.

Foreign-frame proxies reject addon field writes and native widget mutations; the only permitted native mutation is creating an addon-owned texture. Forbidden and inaccessible fixtures reject unsafe member reads. Private texture methods track their arguments; deterministic timer callbacks allow already-queued work to run after cancellation so generation guards are exercised. Tests cover normalization, failed access checks, protected and unprotected restricted regions, unknown unit identity, pooling, border cleanup, picker generations, options capability gates, the Blizzard Settings shortcut, and bounded diagnostics. Native geometry remains unchanged across refreshes and disable/re-enable, including when native dimensions cannot be read. No native layout hooks or CVar writes are installed.

These fixtures do not implement the WoW taint engine. A sentinel can reveal an unchecked secret flowing into operations, but it cannot reproduce every native secret-value behavior. Passing tests establish offline regression behavior only. Actual Retail/Forever appearance, combat actions, engine restrictions, and coexistence with other addons require live validation documented in the audit.

Integration coverage includes independent library namespaces, shared diagnostic headers and bounded reason sampling, copy-window creation/reuse, restriction and native-permission gates, chat fallback after UI construction failure, and suppression of raw foreign error payloads. Changes to embedded library files require upstream review and immutable re-vendoring; verify them with the upstream `scripts/vendor.py --check`.
