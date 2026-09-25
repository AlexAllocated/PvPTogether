# PvPTogether client compatibility

One source tree supports these current client families. Interface metadata permits loading; API capabilities still decide which adapter can run. PTR/beta builds in the same family use those adapters when their contracts match. This does not claim support for arbitrary historical/private-server clients.

| Client family | Source snapshot | Interface targets |
| --- | --- | --- |
| Retail | Installed 12.1.0.69933 UI export | 120100 (existing older Retail targets retained) |
| Forever | Installed 1.60.1.69977 UI export; 1.60.1.70009 spell data | 16001 |
| Era / Hardcore / Season of Discovery | [1.15.9.69722](https://github.com/Gethe/wow-ui-source/tree/33e177d9bf38d76d5c6c6e05d5da78db1899659a) | 11509 |
| Anniversary / Burning Crusade | [2.5.6.69795](https://github.com/Gethe/wow-ui-source/tree/1463c686270b6c64e2c5c228f447c4597c0f8ba6) | 20506 |
| Mists Classic | [5.5.4.69934](https://github.com/Gethe/wow-ui-source/tree/cde55d0033e89b246381385b2f063cd6c6047ef8) | 50504 |
| Titan Reforged (China) | [3.80.2.69874](https://github.com/Gethe/wow-ui-source/tree/84ef503f0d2617494db84cc9c7e7b530e976f6e7) | 38001, 38002 |

The Classic references are mirrored Blizzard UI/API source. Source inspection and offline fixtures establish expected contracts, not engine-level taint safety, rendering or gameplay validation. The user requested source-backed implementation without waiting to level a Forever rogue. Live poison application, expiry, charge exhaustion and audio checks remain pending; no live test result is inferred from these fixtures. No SavedVariables were changed externally.

Every inspected client loads the common `Blizzard_NamePlates.xml` health bar at `UnitFrame.HealthBarsContainer.healthBar`, exposes `NamePlateBaseMixin:GetUnit()`, and registers `Settings.NAMEPLATE_OPTIONS_CATEGORY_ID`. No client-specific native style override is needed or restored.

The same implementation attaches addon-owned category borders to permitted native health bars. It leaves native layout and CVars with Blizzard, guards secrets/forbidden/protected frames, rechecks recycled identities, and retains deferred cleanup. The settings shortcut opens each client's own global nameplate settings. Missing capabilities remain explicit rather than selecting behavior from interface number alone.

Run `lua scripts/test.lua` and `lua scripts/test.lua . reverse` under Lua 5.1/5.2. `tests/clients.lua` covers each current family through border creation, friendly classification, native-settings navigation and disable cleanup, asserting no foreign-field writes, native geometry mutations, hooks or CVar writes. The existing suite covers restriction transitions, recycling, secret values and the shared console.
