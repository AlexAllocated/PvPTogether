# Offline regressions

Run from the repository root with a standalone Lua interpreter:

```sh
lua scripts/test.lua
lua scripts/test.lua . reverse
```

The runner also accepts an absolute repository path as its first argument. Each case loads production Lua into a fresh private environment with an independent database, event dispatcher, timer queue, API fixtures, and frames. None of these files is loaded by the addon manifest, and there is no in-game test command.

Foreign-frame proxies reject addon field writes. Forbidden and inaccessible fixtures reject unsafe member reads. Primitive visual methods track their arguments and journal state; deterministic timer callbacks allow already-queued work to run after cancellation so generation guards are exercised. Tests cover normalization, failed access checks, protected and unprotected restricted regions, unknown unit identity, pooling, rollback, native and third-party layout updates, partial hook installation, border cleanup, picker generations, options capability gates, and bounded diagnostics.

These fixtures do not implement the WoW taint engine. A sentinel can reveal an unchecked secret flowing into operations, but it cannot reproduce every native secret-value behavior. Passing tests establish offline regression behavior only. Actual Retail/Forever appearance, combat actions, engine restrictions, and coexistence with other addons require live validation documented in the audit.
