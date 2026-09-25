# PvPTogether

PvPTogether adds custom border colors to Blizzard's native player nameplates. Configure home-party members, other friendly players, and enemy players separately. NPCs keep their native presentation.

Open **Options → AddOns → PvPTogether** or use `/pt`. Each category has a border toggle, color picker, and reset button. **Blizzard Nameplate Settings** opens the game's global settings, where you can choose the styles available on your client. Layout, names, cast bars, and other native presentation follow those settings. Settings are saved per character in `PvPTogetherDBChar`.

- `/pt on`, `/pt off`, `/pt toggle` control the addon.
- `/pt debug` or `/pt dump` opens the shared debug console with category filtering, fuzzy or quoted search, tail scrolling, copy, clear, test, diagnostics, and reload controls. `/pt dump clear` clears history; `/pt dump STATE` filters state events.
- `/pt diagnostics` opens a copyable build/capability/settings report with bounded diagnostic counters and sampled static reasons. Restricted or unavailable UI falls back to chat.
- `/pt test` runs fifteen checks on detached private values and opens current results in the same debug console, with chat fallback when the window is unavailable. It does not exercise live nameplates or certify taint safety.
- `/pvptogether` is an alias for `/pt`.

The same capability-driven implementation targets Retail, Forever, Era/Hardcore/SoD, Anniversary/TBC, Mists Classic and Titan Reforged. Borders use addon-owned textures attached to accessible native health bars. Protected or inaccessible regions wait until the client permits updates; cleanup retries when restrictions end.

Per-category style overrides have been retired. Old saved style preferences are preserved but ignored. Reload the UI after updating to let Blizzard rebuild its native layout.

Built for Blizzard default nameplates. When reporting a problem, include `/pt diagnostics`, the first error or blocked-action stack, the affected unit category, and the steps that led to the problem.
