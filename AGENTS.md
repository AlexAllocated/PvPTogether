# PvPTogether development

Read `AUDIT_2026-09-24.md` and `FOREVER_COMPATIBILITY.md` before changing client support or nameplate behavior. Treat installed UI exports and the current checkout as evidence; builds and offline fixtures do not establish live-client taint safety.

## Taint and frame ownership

- Keep all addon state in addon-owned tables or addon-created frames. Never add fields to Blizzard frames, child frames, mixins, shared setup tables, or `C_*` tables.
- Access-gate foreign values and tables before comparisons, indexing, iteration, numeric conversion, or diagnostics. Secret or inaccessible results and failed safety queries must fail closed.
- Check forbidden frames before reading other members. Check protected/restriction state before mutations; combat is only one restriction. Capability detection, including Forever, must use actual APIs and shapes rather than interface-number assumptions.
- `pcall` contains errors; it does not remove taint. Do not call Blizzard setup/reset mixins as a shortcut: those methods can write protected fields or shared option tables.
- Use narrow public APIs or read-only secure post-hooks. Never replace Blizzard globals or methods. Sanitize copied primitive data before crossing secure boundaries.
- Preserve native layout updates and recycle identity. Revalidate the live plate/token mapping before applying changes; teardown must be as carefully guarded as setup.
- Fence deferred work with generations. Disabling must invalidate callbacks; retain blocked cleanup for a later unrestricted event, including while disabled.
- Diagnostics may contain bounded, static reason counters and sanitized capability/configuration summaries. Do not record secret values, raw error payloads, unit names, tokens, or GUIDs.

## Validation

- Run `luac -p Core.lua Nameplates.lua Options.lua InGameTests.lua Libs/libchev/*.lua`, `lua scripts/test.lua`, `lua scripts/test.lua . reverse`, and `git diff --check` for behavior changes. Use `stylua --check` on changed Lua files after formatting.
- Tests under `tests/` and `scripts/test.lua` run only in a separate offline Lua process. Never list them in an addon TOC or add an in-game command that loads them.
- `/pt test` may run only `InGameTests.lua` and embedded `SelfTests.lua` using detached private values. Never load offline fixtures through that command; print static case labels and summaries, not raw failure payloads.
- Test production code in fresh private environments with private fixtures. Never patch real Blizzard globals, live frames, mixins, shared UI tables, `issecretvalue`, `hooksecurefunc`, or `C_*` APIs from a live client test.
- Verify regressions through observable behavior: no foreign frame writes, no forbidden/protected mutations, safe unknown-unit classification, recycled plate cleanup, deferred generation invalidation, and disable/re-enable recovery.
- Report offline checks separately from actual Retail/Forever visual, gameplay, and taint validation. Use `/pt diagnostics` for bounded in-game status; it is not a taint certification test.

## Delivery

Preserve existing user work and SavedVariables. Do not overwrite or delete saves without a backup. Release scripts commit, push and tag; run them only when publishing a release is explicitly authorized. Keep audit changes on a reviewable local branch unless publication is requested.

## Shared library

Embed libchev only through its `scripts/vendor.py` from an exact validated commit. The loader contract is `namespace.LibChev`; each addon receives an independent instance under `Libs/libchev`. Never edit embedded library files, create a global registry, or retain the provisional `namespace.Together` alias. Keep nameplate access, restriction, identity, and lifecycle policies in this addon. Preserve the no-identity diagnostics policy and bounded static-reason sampling.

Use `LibChev.NewDebugController` for debug commands, log/filter/search operations, test presentation, diagnostic exports, and the console. Supply only private data, domain reports/tests, and safety policies from PvPTogether; do not recreate generic debug mechanics or UI locally. Keep `failureDetails = false`. Resolve cached controllers with `rawget` so detached fixtures cannot inherit the live addon controller.
