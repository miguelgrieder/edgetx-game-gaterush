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

## During the build

- Mock semantics come from the EdgeTX 2.11 `gui/128x64/lcd.cpp` (summary in `docs/research/lcd_semantics.md`) and fonts decoded from the firmware PNGs — pixel-exact goldens are only meaningful against the real rasteriser — approximate 5x7 font from the renderer.
- Game drawing always passes `FORCE`/`ERASE` explicitly; the default flag is XOR on B&W, so overlapping lines would cancel — rely on the default.
- Reverse-video rows (selected setting, `[ENT] I KNOW`, `NEW BEST!`, out corner) are drawn as text + an XOR `drawFilledRectangle` — matches the mockups' box sizes and costs one call — `INVERS` text (box hugs the glyphs).
- Text is centered with the native `CENTER` flag (exported on B&W in `api_general.cpp`) — the default font is proportional, a fixed 6 px width would be off — width tables in the script.
- Countdown digits are the 3x5 HUD font drawn x4 (12x20) in an 18x24 box placed above or below the quad of that half — the 23x29 box of the mockup covers the quad that spawns at the center — box over the quad.
- RF warning shows the model name inside line 2 ("STICKS TO <NAME>", 11 chars max) — no free line on the 128x64 layout — extra line.
- "NO SAVE" replaces the "TWIN-STICK FPV" subtitle — the title has no free spot — overlapping small text.
- The ENTER release that follows a long press is swallowed by a flag — the real firmware still delivers it and `killEvents` cannot mask ENTER/EXIT on B&W (verified in the simulator) — rely on `killEvents`.
- Menu navigation accepts `EVT_VIRTUAL_NEXT/PREV` (roller), `EVT_VIRTUAL_NEXT_PAGE/PREV_PAGE` (PAGE keys, TX12 without roller) and `EVT_PLUS/MINUS_BREAK` when defined — not every radio has a roller — roller only.
- `TAIL` cause only when the out-episode starts with the quad just behind the tail point and within the tunnel radius of it — a quad flung far away is a hand error even if the nearest segment is the tail — any projection before the tail.
- Cause and tolerance are per side; the first side to exhaust its tolerance names the crash.
- Bot models the hand as an exponential lag (gain 1/(1+delay)) plus wandering noise — the tunnel is a static trail, so pure reaction delay never makes a bot leave it — pure delay.
- Acceleration table tripled (0/45/90/135/180/240 % per minute), speeds unchanged — needed for the average bot to crash in 40–120 s (see TUNING.md) — faster base speed (made the start hectic).
- Outline vertices capped at 45 per tunnel — worst case was 459 draw calls at 1:30 with TRACK_LEN 80 — drawing every 2nd point always (ugly at slow speed).
- Pause RTN (QUIT) is not stored at all (neither best nor average) — the spec says it is not a record; counting it in AVG would punish quitting — count it in AVG.
- CRASHED shows the updated BEST without the mockup's `*` marker — `NEW BEST!` already says it — keep the asterisk.
- No `table`, `os` or string methods in the game — the real firmware sandbox has none of them (found with the Level 2 run); the mock removes them too.
- Level 2 uses the EdgeTX **2.12.4** Companion DLLs driven by Python `ctypes`, not a Docker build of 2.11 — no Docker or compiler on this machine; the DLLs are the same firmware code compiled for PC — Docker build.
- `dist/` is committed — the goal is a file ready to copy to the SD card — generated only.
- `luacheck` was not available; `make lint` also checks the built file's bytecode for global writes (`SETTABUP _ENV`), and the mock fails at runtime on any unknown global read.

## After the first real-radio test (user feedback)

- Defaults changed to CRASH DELAY 0.5 s, SPEED 4, CURVE ACCEL 5, TRACK LEN 25; ranges widened to CRASH DELAY 5.0 s, SPEED 8 (3.2 / 3.9 / 4.7 px per tick added), CURVE ACCEL 8 (300 / 380 / 480 %/min added), TRACK LEN 120 — requested by the player. SPEED ACCEL stays 0–5.
- Tolerance bar under the timer removed — requested; the inverted `L`/`R` corner and the blinking sprite still show the out state.
- The out-alarm cooldown is no longer reset when the quad comes back in — flicking in and out queued a tone + vibration on every re-entry, the likely cause of the lag; now at most one per 250 ms.

## Second round: new tunnels, quads, modes (user request)

- The head now flies **maneuvers** (straight, curve, S, slalom, zigzag, burst, hairpin, stop/reverse, spiral) unlocked by time alive, instead of a pure random walk — readable track sections and less looping — keep tuning the random walk.
- **Stop/reverse** pops points off the head (ring buffer) while the tail waits, never below 8 points, then branches off ±90–135° — the tunnel physically retracts toward the player — a "ghost" reverse that only animates.
- The tail is now an explicit index (`T.tail`) — needed once the head can move backwards.
- **Chokes** store a radius per point; the out test uses the radius interpolated at the projected point and the nearest segment by distance — taking the widest nearby segment let the round ends of the wide parts cover the whole choke.
- **Gates = chokes**: the middle point of each choke; passing it (nearest segment index ≥ gate, while inside) gives +2 s in ENDURO — one mechanic for "narrowing" and "gates" — separate gate objects.
- **SCROLL** keeps world y per point and a camera that only moves up; the head is steered inside a ±57° cone around "up" — the simplest scroller that reuses the same ring, distance and outline code — a separate generator.
- **COUPLE** copies the newest left point into the right ring each tick (mirror / copy / invert), gates included — the right side then needs no generator of its own. INVERT falls back to MIRROR in SCROLL.
- **SEED**: RANDOM runs still pick a seed 1–99 and show it on the result screen, so any run can be replayed — seeds only when fixed. Seed is not part of the record key.
- **Modes**: SPRINT records accuracy %, ZEN records nothing, LEFT/RIGHT ignore the other stick (including on CENTER STICKS). Mode, SCROLL and COUPLE join the record key only when not default, so existing ENDURO records keep their key.
- **Presets** are a view on the six difficulty values (`config.sync` picks the matching preset or CUSTOM) — no separate "preset" state that can disagree with the values.
- **Skins** are 9x9 bitmaps from the sprite sheet turned into rectangles; only the two skins in use are built (`draw.prepare`) to save ~15 KB of heap; the disc under each skin is erased first so tunnel lines don't show through. Prop spin = the full 2x2 corner props shown as their outer diagonal on frame 2 (DISC swaps its erased X for a +).
- **Wreck animation**: 0.6 s where the four props fly away from the crash sprite before the 2-frame flash and the result screen.
- Ring size is exactly 128 (power of two): Lua sizes array parts in powers of two, so 130 would have cost 256 slots per array; TRACK LEN max is 115 for that reason (was 120).
- Outline vertex cap lowered to 38 per tunnel to pay for the bigger quads (skins cost up to 24 calls each), gate posts and HUD numbers.

## Third round: "not enough memory" on a GX12

- The single 47 KB file failed while the radio **compiled** it (the 32 KB version had worked). Measured on the PC with the GC stopped: compiling the single file allocated 271 KB, the 32 KB version 199 KB.
- Split into a small launcher + 8 modules in `/SCRIPTS/TOOLS/GATERUSH/`, loaded with `loadScript` (EdgeTX compiles and caches each as `.luac` on its own). Largest compile now 69 KB (track) — breaks the prompt's "single file, no loadScript" rule, accepted by the user.
- Two groups never in memory together: menus (menus + stats) and play (game + track + draw + fx); the other group is dropped and `collectgarbage()` runs on every switch. Resident heap (PC): menus 64 KB (was 125), play 129 KB (old 32 KB version: 126 KB); peak without forced GC 141 KB (was 258).
- The result screen gets plain values from the play group (`game.result`) before the play group is dropped; records are written by the menus group.
- Tunnel points store only x/y: directions come from neighbouring points and choke radii from a short list of choke centers (`track.rad`) — 3 arrays × 128 × 2 tunnels less.
- Preset logic, labels and value stepping moved from `config` to `menus` (not needed during a run).
- The title icon moved from `draw` to `menus`; countdown/pause overlays moved into `game`.
