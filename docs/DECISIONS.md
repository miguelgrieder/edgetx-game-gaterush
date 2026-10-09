# Decisions

One line each: what — why — discarded alternative.

## Initial (before code)

- References stay in `guide/edgetx-game-references/` (gitignored) instead of `refs/` — that is where they were provided; copying them would duplicate third-party code into the repo — copy to `refs/`.
- Ring buffer: parallel arrays `px, py, pc, ps` (x, y, cos, sin of heading) of size `N = TRACK_LEN + FADE` with `FADE = 9` — zero allocation per frame, normals precomputed at generation — table of point tables.
- One centerline point per simulation tick (50 ms), spaced by the current head speed — length in points is what the spec fixes; length in px grows with speed — fixed-distance resampling.
- Tail policy: the tunnel grows from 1 point at spawn up to `TRACK_LEN` points (tail parked at spawn until then), then the tail advances one point per tick; the 9 points behind the tail fade in 3 ages of 3 points (50 % → 25 % → 12 % → gone) — matches `fade_len` in the renderer — one point per age (too short to see).
- Outline: two offset polylines (centerline ± normal·RT) plus a semicircle cap at each end, drawn with `drawLine`; vertices decimated to one every ~4 px (stride anchored to the absolute point sequence so it does not shimmer) — pixel union of discs from the renderer costs thousands of `drawPoint` — every-point vertices exceed 300 calls at TRACK_LEN 80.
- Fading uses the native `drawLine` pattern byte (0x55 / 0x11 / 0x01) — one call per segment — per-pixel dither with `drawPoint`.
- Draw order: divider, tunnels, dust, quads, HUD, overlays (countdown box, pause box) — quads must stay visible over the tunnel.
- Countdown/resume box is drawn before the quads so the quad (spawned at the center of the half, under the box) stays visible — box drawn last would hide the quad the player is steering.
- Module inlining: `tools/build.lua` wraps each `src/*.lua` in `local name = (function() ... end)()` in dependency order and deletes the matching `local name = require("name")` lines — keeps `require` in dev and gives a single file with no globals — a custom loader table.
- Config "hash" is a readable key such as `m2d3s3a2c2t40` — collision-free and debuggable — numeric hash.
- Each tunnel has its own Park-Miller generator seeded from `getTime()` and the side — independent, deterministic in tests — global `math.random`.
- Curvature is limited in 1/px (min turn radius `RT+3`) so the inner edge never folds badly; it grows with `CURVE_ACCEL` — curvature in rad/tick (would flatten curves as speed grows).
- Out test: point-to-segment distance against the raw centerline in a ±12 index window around the last nearest index, full scan when the window says "out" — cheap per tick and robust when the tunnel loops back near the quad — full scan always.
- Tail rule: quad projection before the tail point (t < 0 on the first segment) = out with cause `TAIL`.
- `CRASH_DELAY` in ticks = round(delay·20); crash on out-tick number `max(1, ticks)` (0 → first frame, 0.3 → 6th) — matches §9.
- License MIT — simplest permissive choice; nothing from GPL games is copied, only patterns — GPL-2.0.
