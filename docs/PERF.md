# Performance

Proxy for the radio CPU: number of `lcd.*` calls per frame, counted by the mock (`tools/run_frames.lua`
writes `draw_calls_max/avg` to `metrics.json`). Budget: **≤ 300 per frame**. Memory is the Lua heap
of the PC interpreter after a full GC (64-bit, so roughly 1.5–2× what a 32-bit radio uses).

## Draw calls per scenario (target `src`, `lua5.2 tools/run_frames.lua --script inputs/<name>.lua --nopbm`)

Max includes every frame of the scenario (menus included); avg is over the whole run.

| scenario | frames | max | avg |
|---|---|---|---|
| 00_rf_warning | 5 | 9 | 9 |
| 01_title | 20 | 48 | 30 |
| 02_center_sticks | 25 | 48 | 27 |
| 03_countdown | 40 | 83 | 42 |
| 04_play_start (0:07) | 231 | 179 | 115 |
| 05_play_out_tolerance | 331 | 180 | 133 |
| 06_play_final (1:32) | 1936 | 181 | 169 |
| 07_pause | 1946 | 183 | 169 |
| 08_resume_countdown | 1976 | 193 | 169 |
| 09_crashed | 311 | 192 | 124 |
| 10/11_settings | 40 | 48 | 23 |
| **perf_worst** (TRACK_LEN 80, MARGIN 5, to 1:35, both quads out every 10 s) | 1991 | **287** | 243 |
| soak: 100 games with the bad bot | 26011 | 208 | – |

## Where the calls go (worst case)

- outline: 2 lines per vertex per tunnel; vertices every ~4 px but **at most 45 per tunnel**
  (`track.MAXV`) → ≤ 176 lines
- rounded ends: 8 lines × 2 ends × 2 tunnels = 32
- quads: 8 calls each (5 rects + 2 erase diagonals + 1 point), 20 when the crash sprite shows
- HUD: timer 4 glyphs of 2–5 rects, `L`/`R`, tolerance bar 2, inverted corners 2
- dust 10 points, divider 1, `lcd.clear` 1

Before the vertex cap, the worst case was **459** calls (at 1:30 the head moves 3.5 px/tick, so every
point became a vertex). The cap keeps a 2-point stride at TRACK_LEN 80, which still follows the turn
radius limit (`RT+3`) closely.

## CPU per frame (other than drawing)

- 2 tunnel steps (1 cos/sin pair each, clamping) per 50 ms tick
- distance check: ±12 segments around the last nearest index (25 point-segment distances per tunnel);
  a full scan (≤ 80 segments) only when the window says "out" or its best is on a window edge
- no table, closure or string creation in PLAY: ring buffers are preallocated parallel arrays, the timer
  digits are recomputed only when the second changes and drawn as rectangles (no `string.format`)

## Memory (PC Lua 5.2, 64-bit)

| | KB |
|---|---|
| built script after load (code + constants + preallocated arrays) | 112.6 |
| steady state after 1500 frames (after GC) | 116.2 |
| growth over 500+ frames, any scenario | < 0.4 (criterion: < 2) |
| growth over 100 consecutive games (soak) | −0.3 |

Compiled size per module with debug info (`string.dump`): main 14.0 KB, track 10.6, screens 9.0,
game 8.4, draw 8.1, config 6.1, stats 3.8, fx 2.4, input 2.3. For comparison, on the same interpreter
`Doom.lua` compiles to 38.7 KB and `PocketPet.lua` to 73.0 KB; GateRush to 86.8 KB. On the radio the
firmware compiles `gaterush.lua` to `gaterush.luac` **without debug info** (default load mode `bt`) and
uses 32-bit values, so the real footprint is smaller, but the first compile on a TX12 MK1 (128 KB RAM)
is the step most likely to run out of memory — see the real-radio checklist in `REPORT.md`.

## Level 2 timing

The firmware simulator runs on the PC CPU, so `getUsage()` there says nothing about the STM32F205.
On the radio, `getUsage()` can be shown temporarily (see REPORT) to read the real budget use.
