# PvPTogether

PvPTogether adds per-category bar/name geometry and optional border tint to Blizzard's native nameplates. Configure actual home-party members, other friendly players, and enemy players separately. NPCs keep their native presentation.

Open **Options → AddOns → PvPTogether** or use `/pt`. Each category offers six geometry choices, an **Inherit From Global** option, a border toggle, a color picker, and a reset button. Settings are saved per character in `PvPTogetherDBChar`.

- `/pt on`, `/pt off`, `/pt toggle` control the addon.
- `/pt diagnostics` opens a copyable build/capability/settings report with bounded diagnostic counters and sampled static reasons. Restricted or unavailable UI falls back to chat.
- `/pt test` runs twelve checks on detached private values. It does not exercise live nameplates or certify taint safety.
- `/pvptogether` is an alias for `/pt`.

The current local beta targets Retail 12.1 and the Forever 1.60.1 beta. Forever uses modern nameplate APIs and restrictions. Live-client validation is still required; interface metadata alone is not proof of compatibility.

Overrides change bar/name geometry. Name colors, selection behavior, click areas, stacking dimensions, and Forever level-badge dimensions continue to follow Blizzard's global style. The global Classic preset keeps its native geometry. Accessible unprotected visuals can update during PvP when the client permits it; protected or inaccessible regions wait until restrictions end.

Built for Blizzard default nameplates. When reporting a problem, include `/pt diagnostics`, the first error or blocked-action stack, the affected unit category, and the steps that led to the problem.
