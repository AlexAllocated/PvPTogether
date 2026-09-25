# Per-category style reliability review

September 24, 2026. Reviewed PvPTogether `73e0def4f9e905e4b8831abf306e666f4b24d161`, the installed Retail/Forever UI exports, and the user's Forever build 70009 reports. No production behavior changed during this review. Earlier visual confirmation established that styles could apply, not that they remained reliable through gameplay transitions.

**Recommendation: retire per-category native style overrides from PvPTogether. Keep category border colors and provide access to Blizzard's global nameplate settings.** There are fixable lifecycle bugs, but the current feature also promises more than its partial geometry adapter can deliver. Cosmetic nameplate customization remains supported in principle; this recommendation concerns this implementation and its maintenance cost, not a claim that all nameplate styling is impossible.

## Confirmed implementation weaknesses

1. **Every refresh dismantles the existing override first.** `Nameplates.lua:1088` restores the journal before classification at line 1106 and before building the replacement plan at line 1124. A temporarily inaccessible classification or required layout value can therefore remove a previously working style even when Blizzard did not reset it.
2. **Some failures lose the retry request.** The full refresh clears the pending flag at line 1208. Unknown classification and `BuildPlan` failure return without setting it again. Becoming readable later is not itself an event; the plate can remain native until some unrelated refresh. `layout-unavailable` also lacks the precise failure detail supplied by the later execution preflight.
3. **Native layout is intentionally applied before PT reasserts its geometry.** `OnNativeNameplateLayout` retires the affected journal group and schedules a callback after 0.05 seconds. A successful follow-up still permits a native-layout interval; if safety or geometry checks fail, no override is applied. Polling more often would not grant access to restricted values or frames.
4. **The preset is only partly implemented.** `BuildPlan` changes cast/health heights, name/health text fonts and anchors, and the debuff vertical anchor. The native style still controls root plate dimensions/stacking, click regions, level indicators, and native behavior fields. They cannot be made equivalent by simply reapplying the current 15 operations more often.

## Reproduction evidence

The separate offline characterization script below loads the production addon into `tests/harness.lua` private fixtures. It does not touch the game, SavedVariables, or native globals. Run against the reviewed revision with either Lua 5.1 or 5.2:

```sh
lua scripts/review_style_lifecycle.lua .
```

Both interpreters produced the same observations. These are fixture dimensions, not measured live pixels:

| Scenario | Result |
| --- | --- |
| Ordinary `PLAYER_TARGET_CHANGED`, with all data available | Override remains at height 16, but the refresh performs 52 primitive visual mutations including restoration and reapplication. |
| Same refresh while `showOnlyName` is temporarily absent | Cast returns to native baseline 20; journal empty; no pending refresh or queued timer; border remains visible. |
| Flag becomes readable with no new event | Cast remains at baseline 20. |
| Classification is temporarily inaccessible | Cast returns to baseline 20; border hides; no pending refresh or queued timer. |
| Native layout changes while fixture frames are protected in combat | Native cast height 10 remains; PT performs zero mutations. This illustrates the required restriction boundary, not a bug to bypass. |

The first two failure scenarios establish mechanisms for the reported symptom. They do not identify the exact live event or value that triggered every user-visible reset. Existing offline regression success did not cover this continuity contract and does not prove live reliability.

## Native source and QT comparison

Paths below are relative to the installed client's `BlizzardInterfaceCode/Interface/AddOns` export:

- `Blizzard_NamePlates/Blizzard_NamePlateBase.lua:29`: setting a unit applies native frame options. `ApplyFrameOptions` at line 62 supplies the global `NamePlateSetupOptions`.
- `Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua:197`: native option passes set dimensions/fonts and call `UpdateAnchors`. At line 676, `UpdateAnchors` reads the global setup again. Name-only changes also call it at line 583.
- `Blizzard_NamePlates/Blizzard_NamePlates.lua:396`: level-indicator size depends on global style. `GetNamePlateHeight` at line 510 calculates the global layout/stacking dimensions.
- `Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua:587`: click regions depend on global style. PT deliberately does not change them.
- `Blizzard_NamePlates/Blizzard_NamePlateCastingBar.lua:26`: calling the native styling helper is not an equivalent safe fix; it also writes Blizzard-owned behavior fields.
- QT's `Nameplates.lua:3137` anchors its own fill overlay to the existing health texture. It follows native geometry instead of replacing that geometry, which is a smaller ownership boundary than PT's style journal.

Blizzard explicitly describes cosmetic nameplate/cast-bar customization as an intended capability in [Combat Philosophy and Addon Disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight). That does not provide a persistent per-unit native preset API. The installed nameplate API documentation does not expose one.

## Proposed product change

- Remove per-category style dropdowns and their style previews; expose a button to Blizzard's global nameplate settings.
- Keep party/friendly/enemy border enable controls and colors, the shared console, and diagnostics.
- Retire native geometry mutations, layout snapshot observers, and style reapplication hooks. Keep only lifecycle, restriction, identity, and cleanup work required by the owned border overlays; decouple borders from native style-hook installation.
- Preserve old saved style values as ignored data so retirement does not destructively rewrite user preferences. Existing live geometry should return to native after `/reload`; do not force native setup helpers or overwrite saved files.

If per-category geometry is retained instead, it needs a lifecycle redesign: validate identity and the replacement plan before changing a valid layout, handle every deferred outcome explicitly, avoid unnecessary restore/reapply passes, and test continuity across native refresh, pooling, target/focus, casting, name-only mode, settings changes, and restrictions. Even then the feature must be described as limited geometry customization, with native fallback where access is unavailable. That is materially more work than another hook or timer adjustment.
