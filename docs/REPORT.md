# GateRush — final report

## What was done

- **Game**: `dist/SCRIPTS/TOOLS/gaterush.lua` (single file, 32 KB, first line `-- TNS|GateRush|TNE`, ends with
  `return { init = init, run = run }`) plus the `dist/SCRIPTS/TOOLS/GATERUSH/` save folder. All 12 screens of
  the mockups: RF warning (with model name), title, settings (2 pages), center sticks, countdown, play,
  out-tolerance, pause, resume countdown, crashed. Rules of §1 implemented: absolute stick mapping onto the usable
  area (recomputed from MARGIN), tunnels with fading tails, out by quad center, CRASH_DELAY tolerance with
  reset, tail crash, 1.5 s protected start, speed/curvature ramps, 250 ms beep + haptic cooldown, per-config
  BEST/AVG, `.cfg`/`.dat` persistence with tolerant parsing and `NO SAVE` fallback, backlight reset.
- **Sources**: `src/` (9 modules), built by `tools/build.lua`.
- **Tests**: 62 tests in `tests/` — draw (sprites vs mockup sprite #1, font, dither, clipping), config, stats,
  input (4 stick modes, mapping, MARGIN), track (10,000 confined steps × 6 radii, ring buffer, distance, outline
  golden), rules (all of §9's timing rules, feedback timestamps, pause/resume), 12 screen goldens rendered from
  `src/` plus the 6 non-bot ones from the built `dist/` file.
- **Mock** faithful to the firmware rasteriser; **frame runner**; **bot**, **calibration**, **soak**.
- **Level 2 executed**: the built game ran inside the real EdgeTX 2.12.4 firmware (Companion simulator DLLs
  driven headlessly from Python) on TX12, TX12 MK2, Boxer, Pocket and GX12. That run found a real bug the first
  mock missed (string method calls do not exist on the radio), fixed in the game and now enforced by the mock.
  After the fix, 7 reference screens (including a graphics self-test of patterned lines and sprites) are
  **pixel-identical** between the mock and the firmware.

## Acceptance criteria (§9)

| criterion | status |
|---|---|
| `make test` green | ✓ 62/62 (run with `lua52.exe tests/run_all.lua`; `make` itself is not installed on this machine) |
| luacheck clean | **not run** — luacheck is not installed. Substitute: no `SETTABUP _ENV` (global write) in the built bytecode; every global read checked against the API list; the mock errors on unknown globals |
| `make frames`: 600 frames per scenario, no errors, stable memory, no negative coords, no non-B&W calls | ✓ 13 scenarios, memory growth ≤ 0.31 KB (the mock errors on any negative/off-screen coordinate or missing API) |
| worst case ≤ 300 draw calls | ✓ 287 (TRACK_LEN 80, MARGIN 5, 1:35, both quads out), see `PERF.md` |
| perfect bot survives 5 min; average bot crashes in 40–120 s | ✓ perfect 20/20 at 300 s; average: avg 89.5 s, 50–128 s (19 of 20 runs inside the window), see `TUNING.md` |
| dist file header/footer, runs in the runner, passes the goldens | ✓ |
| 12 screens match the mockups in layout | ✓ approved after visual comparison; deliberate deviations listed in `DECISIONS.md` (countdown box size/position, model name placement, NO SAVE, no `*` after BEST) |
| CRASH_DELAY=0 kills on the first frame out; 0.3 tolerates 5 and kills on the 6th; coming back resets | ✓ `test_rules.lua` |
| MARGIN changes radius and stick mapping; any difficulty setting changes the displayed BEST | ✓ `test_input.lua`, `test_config.lua` |
| Level 2 executed | ✓ (2.12.4 DLLs, not a Docker build of 2.11; see DECISIONS) |

## Decided on my own

See [`DECISIONS.md`](DECISIONS.md). The most visible ones: acceleration table ×3 to reach the target difficulty,
countdown box moved above/below the quad, swallowed ENTER release after the long press (firmware cannot mask it),
`TAIL` blamed only while the quad is near the tail end, outline vertex cap.

## Numbers

- Draw calls: menus ≤ 48, play 115–170 average, ≤ 193 in normal scenarios, 287 worst case.
- PC Lua heap (64-bit, with debug info): 112.6 KB after loading the script, flat over 100 games (±0.4 KB).
- Calibration: SPEED 3 / ACCEL 2 → average bot 90 s.

## Left out

- Real hardware runs (not available here).
- `luacheck` (not installed).
- A pure Docker build of the firmware (Level 2 used the official Companion DLLs instead).
- Circle offset tables r=1..9 from §5: never needed — the only circles are the quad (rect rows) and the rounded
  tunnel ends (rotated semicircle, 8 segments).

## What to test on the real radio (short list)

1. **Memory / first launch on a TX12 MK1** (128 KB RAM): does the first launch compile and start, or does it
   show "not enough memory"? This is the main risk (the script is about the size of PocketPet.lua). If it fails,
   tell me: the fix is to shrink the code (merge modules, drop the settings labels table).
2. **CPU**: is the game smooth at 1:30 with TRACK_LEN 80? (Draw calls are within budget; real ms are unknown.)
   If it stutters, lower `track.MAXV` (45) to ~32.
3. **Feel of the speed**: is SPEED 3 / ACCEL 2 a good warm-up, and is +90 %/min too steep? Is CRASH DELAY 0.3 s fair?
4. **LCD ghosting**: are the fading tail dots (50/25/12 %) and the blinking crash sprite readable on the real
   panel, or do they smear?
5. **Haptic**: is the 40 ms pulse every 250 ms noticeable but not annoying?
6. **Settings navigation**: on your radio, do the roller (or PAGE keys on a TX12 without roller) move through
   the list and change values? Does holding ENT on the title open settings without editing MARGIN?
7. **Throttle**: centering a non-spring throttle on CENTER STICKS — is ±8 % too tight?
