# Retail and Forever compatibility evidence

Reviewed September 24, 2026. Installed build metadata still reports Retail **12.1.0.69933** and Forever beta **1.60.1.69977**. The comparison below uses the actual `BlizzardInterfaceCode/Interface` exports in those installations. It is a source audit, not a successful login, screenshot comparison, combat test, or taint certification. The original PvPTogether implementation inspected was commit `ec3d4df077ad465c7260de1f3d95252382c9684b`.

**Verdict:** the addon’s purpose is viable on Forever, but it needs the modern nameplate implementation and modern restriction checks. Treating interface `16001` as old Classic would select the wrong API and security behavior. A TOC change alone cannot provide compatibility. Keep the same capability-driven implementation for both clients, with explicit handling of Forever’s different layout and a safe fallback wherever a region or classification is unavailable.

## What the clients actually provide

Dropdown follow-up: the shared enum is broader than the choices Blizzard exposes. The installed Forever export's `Blizzard_SettingsDefinitions_Frame/Camelot/NameplatesOverrides.lua` supplies Thin (Default), Modern (Large), Block, and CastFocus in that order. PvPTogether now reads `NameplatesOverrides.GetNameplateStyleOptions`, the provider used by the global setting, instead of treating every enum member as selectable. Older installed Retail code keeps that callback in the registered `nameplateStyle` dropdown initializer; the addon reads its options without opening or modifying Settings. Unsupported saved overrides inherit the current global style, and unavailable option data offers no guessed presets.

| Area | Verified behavior and consequence |
| --- | --- |
| Unit categories | Both exports expose `UnitIsPlayer`, `UnitIsFriend`, and `UnitInParty`; Forever references are `UnitDocumentation.lua:2271–2284`, `1977–1990`, and `1637–1650`. The player/friendly/enemy/party distinction remains feasible. An inaccessible or failed query must remain unknown rather than becoming an NPC or enemy. |
| Plate lookup | `C_NamePlate.GetNamePlateForUnit(unit, false)` deliberately excludes forbidden plates. The export documents the flag at `NamePlateDocumentation.lua:11–24`. Blizzard’s driver passes `issecure()` itself at `Blizzard_NamePlates.lua:113`, so copying its unrestricted context assumptions into addon code would be incorrect. |
| Modern layout | Both clients put the cast bar inside `UnitFrame.CastBarsContainer.castBar`. Retail `Blizzard_NamePlateUnitFrame.lua:196–238` and `663–685`; Forever `197–244` and `675–713`. The original addon requires `UnitFrame.castBar`, so its anchor routine exits without styling these current frames. |
| Style representation | Both expose Modern, Thin, Block, HealthFocus, CastFocus, Legacy, and Classic (`NamePlateConstantsDocumentation.lua:121–135`). Modern setup uses `unitNameAnchorStyle`, not the original addon’s `unitNameInsideHealthBar` field. Styles also affect spacing, textures, selection behavior, and whether the spell icon is hidden for an uninterruptible cast. |
| Forever dimensions | The loaded Camelot constants use small health/cast heights **13/6**, health font height **14**, cast icon height **10**, and plate width **190**. Retail uses **10/10**, **12**, **12**, and **230**. Read the loaded constants; copying Retail numbers is incorrect. See Forever `Camelot/Blizzard_NamePlateConstants.lua:31–48` and Retail `Blizzard_NamePlateConstants.lua:28–42`. |
| Forever name/level layout | Camelot selects centered outlined text above the health bar (`Camelot/Blizzard_NamePlateFrameOptionsOverrides.lua:1–3`). The level indicator reserves horizontal space and moves adjacent raid/crowd-control indicators (`Blizzard_NamePlateUnitFrame.lua:680–711`, `824–857`). It is not just Retail with a different interface number. |
| Secret values | Forever explicitly marks `UnitGUID` as secret when identity is restricted (`UnitDocumentation.lua:1241–1254`) and `UnitIsUnit` as secret when comparison is restricted (`2410–2425`). A `pcall` that succeeds does not make a return value safe to compare, branch on, index with, or log. |
| Restricted objects | `IsForbidden`, `IsProtected`, `IsAnchoringRestricted`, and `IsShown` can themselves have secret returns. `ClearAllPoints`, `SetPoint`, `SetHeight`, and `SetSize` are protected methods. Check access and restrictions before mutation, including every child and relative anchor. An exception while checking restrictions must fail closed. |
| CVars | Both clients retain the nameplate style/size/aura/debuff-padding CVars in their loaded constants. `C_CVar.GetCVarInfo` exposes lock/secure/read-only status, and `SetCVar` has an explicit success return and access preconditions. Do not infer successful writes from an error-free `pcall`, and do not use repeated global CVar changes to switch style per unit. |

Forever’s addon TOC explicitly loads its Camelot constants and option overrides (`Blizzard_NamePlates.toc:5–8`), so the generic constants elsewhere in the same export are not the values to use for this client. Its UI already enables native pixel rounding for nameplates; `Blizzard_SharedXML/PixelUtil.lua:38–59` marks the old per-call rounding helpers deprecated. Calling those helpers also introduces arithmetic on the region’s effective scale, so primitive setters with validated inputs are the smaller dependency surface.

## Shared-state and taint boundaries

Neither installed export contains a `SetUnitFrameOptions` nameplate API. The actual setup path is `NamePlateBaseMixin:ApplyFrameOptions`, which enters `CompactUnitFrame_SetUpFrame` and `NamePlateUnitFrameMixin:ApplyFrameOptions`. The latter calls `CompactUnitFrame_SetOptionTable`, whose implementation assigns `frame.optionTable = optionTable` (`Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:314–321`). Passing an addon-owned copy into that path transfers addon data into Blizzard-owned state. `UpdateAnchors` subsequently reads the global `NamePlateSetupOptions` anyway, so that call would not establish a durable per-unit style.

Other seemingly visual helpers also write Lua state: Retail `NamePlateCastingBarMixin:ApplyStyleAndAnchoring` writes `classicStyleCastBar` and `HideIconWhenNotInterruptible` (`Blizzard_NamePlateCastingBar.lua:24–26`) and `Spark.offsetY` (`61`, `96`). The driver’s `UpdateNamePlateOptions` rewrites global setup/friendly/enemy tables (`Blizzard_NamePlates.lua:543–590`; Forever `555–609`). Calling these from addon code, including during disable/reset, is not a safe way to restore a clean Blizzard state. Catching errors does not remove taint from written fields.

The appropriate implementation boundary is:

1. Resolve accessible unit classification separately from rendering. Keep frame/token/GUID associations, applied state, overlay handles, and deferred generations exclusively in addon-owned tables. Never cache secrets. An unknown current identity must not inherit a recycled unit’s classification.
2. Build private geometry from validated scalar configuration and the loaded client constants. Do not mutate or replace global option tables, mixins, cached Blizzard fields, or C API tables. Do not invoke Blizzard setup helpers with addon payloads.
3. Apply only guarded primitive visual operations on accessible regions. Avoid native nameplate-root sizing and hit-test changes. Both clients document a special combat/tick rule for hit-test mutations (`FrameAPINamePlateDocumentation.lua:10–27`, `60–68`); these are not ordinary texture changes.
4. Preserve Blizzard’s global behavior where a per-type difference would require writing its state. Classic is especially sensitive because cast behavior and selection behavior differ in addition to geometry. Any deliberately unsupported style or presentation detail must be visible in the options/help rather than silently pretending to match the full Blizzard preset.
5. Guard teardown with the same checks as setup. Retain handles for pending cleanup, invalidate old callback generations across disable/re-enable, and retry deferred work through state-change events after restrictions end. Do not restore a stale snapshot over a newer Blizzard layout or another addon’s current changes.
6. Use addon-owned wrappers and private fixtures for regressions. Live tests must never replace `issecretvalue`, `C_*`, `hooksecurefunc`, Blizzard mixins, or other shared client objects.

These choices reduce known shared-state coupling. Offline tests cannot establish whether the engine considers a particular live frame mutation safe, and a clean login alone does not establish clean combat behavior.

## Public guidance and practical use

Blizzard’s [addon-disarmament explanation](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight) explicitly preserves visual customization of nameplates and cast bars while restricting computational use of combat data. PvPTogether’s static per-category presentation fits that design direction. This is not a promise that every frame or helper remains accessible.

Blizzard’s [Forever ruleset explanation](https://news.blizzard.com/en-us/article/24302070/choose-your-ruleset-in-world-of-warcraft-forever) confirms world PvP, party play within rulesets, faction-separated groups, and battlegrounds. These give the addon’s enemy/friendly/party categories useful applications. The source does not establish current arena availability or certify addon compatibility, so an arena test is required on Retail and only where actually available in Forever.

The installed generated API documentation is the primary evidence for Forever’s restrictions here. Community posts claiming complete Retail API parity are not used as a technical guarantee. Plater’s official source at inspected commit `99860a925aac6317061aa8ec4098f1be70c517df` provides a corroborating design reference: its [`Interface-Camelot: 16001` declaration](https://github.com/Tercioo/Plater-Nameplates/blob/99860a925aac6317061aa8ec4098f1be70c517df/Plater.toc#L7) and [`DF.IsMidnightWowAPI()` routing](https://github.com/Tercioo/Plater-Nameplates/blob/99860a925aac6317061aa8ec4098f1be70c517df/libs/DF/fw.lua#L268) show why a low interface number must not select old-Classic assumptions. Its internal frame mutations are not a blanket precedent for this addon.

## Required live validation

- Start each client with only PvPTogether and error-capture tools. Check all supported styles on NPCs, friendly players, hostile players, and party members at small/default/large nameplate sizes. Compare name, health text, cast icon/text, interrupt shield, auras, and selection borders.
- In Forever, inspect level badges and skulls, centered names, name-only friendlies, crowd-control icons, and widgets-only units. Validate both level-bearing and level-hidden states. Retest after beta updates because these layouts differ from Retail.
- Change category styles and border colors during combat; finish combat and verify the latest requested setting applies without blocked actions. Disable and re-enable during combat and while delayed work is pending. Removal/reuse must not leave a previous unit’s tint or style on a new unit.
- Enter/leave battlegrounds and instances; test Retail arenas. Include friendly restricted nameplates. Verify skipped restricted frames keep their native display and that cleanup resumes when access returns.
- Change Blizzard’s global style/size while the addon is enabled, including Classic if the client offers it; disable the addon and verify current native presentation is preserved. Check rapid targeting, faction changes, group membership changes, and loading screens.
- Repeat with the user’s ordinary addon set. Capture the client build, PvPTogether diagnostics, first error/blocked-action stack, selected unit category/style, and action immediately preceding a failure. Reload and full-restart settings persistence are separate checks.

No existing saves or client configuration files were changed by this research. No release was published.

## Local source roots

- [Retail export](</home/alx/.local/share/Steam/steamapps/compatdata/2527490029/pfx/drive_c/Program Files (x86)/World of Warcraft/_retail_/BlizzardInterfaceCode/Interface/AddOns>)
- [Forever export](</home/alx/.local/share/Steam/steamapps/compatdata/2527490029/pfx/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/BlizzardInterfaceCode/Interface/AddOns>)
- [Installed build metadata](</home/alx/.local/share/Steam/steamapps/compatdata/2527490029/pfx/drive_c/Program Files (x86)/World of Warcraft/.build.info>)

All source references above are relative to the appropriate export’s `AddOns` directory. Bare nameplate filenames are under `Blizzard_NamePlates`; bare generated-documentation filenames are under `Blizzard_APIDocumentationGenerated`. Restriction references: Forever `FrameScriptDocumentation.lua:48–78`, `SimpleFrameScriptObjectAPIDocumentation.lua:242–253`, `SimpleScriptRegionAPIDocumentation.lua:398–422`, `538–590`, and `SimpleScriptRegionResizingAPIDocumentation.lua:22–25`, `124–178`. Retail CVar references: `CVarDocumentation.lua:82–100`, `117–134`.
