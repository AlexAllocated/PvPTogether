# Offline regressions

Run from the repository root with a standalone Lua interpreter:

```sh
lua scripts/test.lua
lua scripts/test.lua . reverse
```

The runner also accepts an absolute repository path as its first argument. Each case loads production Lua into a fresh private environment with an independent database, event dispatcher, timer queue, API fixtures, and frames. No offline runner or fixture file is loaded by the addon manifest. The separate `/pt test` command runs only the ten detached library self-tests and two pure addon checks from `InGameTests.lua`. The offline suite also registers those exact twelve bodies and verifies that running the live entry point does not alter addon settings, diagnostics, frame state, hooks, or timers.

Foreign-frame proxies reject addon field writes. Forbidden and inaccessible fixtures reject unsafe member reads. Primitive visual methods track their arguments and journal state; deterministic timer callbacks allow already-queued work to run after cancellation so generation guards are exercised. Tests cover normalization, failed access checks, protected and unprotected restricted regions, unknown unit identity, pooling, rollback, native and third-party layout updates, partial hook installation, border cleanup, picker generations, options capability gates, and bounded diagnostics.

These fixtures do not implement the WoW taint engine. A sentinel can reveal an unchecked secret flowing into operations, but it cannot reproduce every native secret-value behavior. Passing tests establish offline regression behavior only. Actual Retail/Forever appearance, combat actions, engine restrictions, and coexistence with other addons require live validation documented in the audit.

Integration coverage includes independent library namespaces, shared diagnostic headers and bounded reason sampling, copy-window creation/reuse, restriction and native-permission gates, chat fallback after UI construction failure, and suppression of raw foreign error payloads. Changes to embedded library files require upstream review and immutable re-vendoring; verify them with the upstream `scripts/vendor.py --check`.
