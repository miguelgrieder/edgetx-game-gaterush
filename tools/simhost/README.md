# simhost: run a Lua tool in the real EdgeTX firmware, headless

`simu_host.py` loads the Companion simulator DLL (`libedgetx-<radio>-simulator.dll`, real firmware
compiled for PC) with Python `ctypes`, boots it, launches a Lua tool from the TOOLS menu, injects
sticks and keys, and dumps the 128x64 LCD as PBM files. Stdlib only, Windows x64 only.

## Get the DLLs (once, nothing installed system-wide)
Companion for Windows (`edgetx-cpn-win64-vX.Y.Z.zip` on GitHub releases, tested with 2.12.4) contains an
NSIS installer. Unpack it with 7-Zip (`7z x companion-windows-*.exe -oinst`) and use `inst/bin` as
`--dll-dir` (needs `Qt6Core.dll`, `SDL2.dll` and the `libedgetx-*-simulator.dll` files; the MSVC runtime
is already on Windows). Available B&W radios include tx12, tx12mk2, boxer, pocket, gx12, zorro, x7...

## Run
    python tools/simhost/simu_host.py --dll-dir <inst/bin> --radio tx12 --sd dist --tool GateRush \
        --inputs inputs/run1.txt --out out/simu/run1

* `--sd` is copied to `<out>/_sd` (missing RADIO/MODELS/SETTINGS dirs are created); your folder is never touched.
* `--tool` is the display name from the script header `-- TNS|GateRush|TNE` (file in `SCRIPTS/TOOLS/`).
* Without `--inputs`, records `--frames` frames (default 100, 50 ms each) with idle sticks.
* Other options: `--frame-ms`, `--boot-ms` (3500), `--tail` (ms recorded after last input line, 500),
  `--nav "sys,next,enter"` (custom launch key sequence), `--no-launch`, `--stop-keys`.

Outputs in `--out`: `frame_NNNN.pbm` (P1, `1` = dark pixel), `log.txt`, and `firmware_trace.txt`
(everything the firmware prints: Lua `print()`, Lua syntax/runtime errors, storage warnings).
`python -c` PBM viewers: any viewer that reads P1, or convert with PIL (`Image.open`).

## Input file
One step per line, `#` starts a comment:

    t_ms  ail  ele  thr  rud  [key]

* `t_ms`: time since recording started (monotonic increasing).
* sticks are raw `-1024..1024` (what `getValue('ail')` etc. return) and **persist** until the next line.
  Initial state (boot and launch): ail/ele/rud = 0, thr = -1024 (so no throttle warning).
* `key` (optional, one-shot at that time): `none enter exit next prev enter_long exit_long` or any of
  `menu pageup pagedn up down left right plus minus model tele sys` (`_long` suffix works on all).
  Short press = 120 ms, long = 700 ms. `next/prev` = `+`/`-` keys (rotary radios too, see Observed events); `rot_next/rot_prev` = raw rotary-encoder step.

Example:

    0    0 0 -1024 0
    500  1000 0 -1024 0 none
    1000 0 0 -1024 0 enter

## Observed (TX12, boxer, pocket, gx12 identical; EdgeTX 2.12.4)
* Sticks reach `getValue('ail'|'ele'|'thr'|'rud')` with the same sign and range as given (+1000 -> 1000).
  Analog indexes: rud=0, ele=1, thr=2, ail=3.
* (superseded by the table below) script event numbers on B&W: ENTER press `98` (first) then release `34` (= `EVT_VIRTUAL_ENTER`);
  EXIT `97` then `33` (= `EVT_VIRTUAL_EXIT`); long ENTER `98`, `130` (long), `66`, `34`;
  next (rotary/+) `105` then `41`; prev `106` then `42`. `EVT_VIRTUAL_NEXT`=4100, `PREV`=4099 are
  constants only; the tool receives the raw key events above on these radios.
* Launch path: `exit,exit` (dismiss warnings), `SYS` -> tools page, `next` x (index of the tool among
  `SCRIPTS/TOOLS` entries sorted by file name), `enter`.

## Observed events (EdgeTX 2.12.4 simulator; tx12 and boxer give identical results)
Key index k (firmware `EnumKeys`): menu 0, exit 1, enter 2, pageup 3, pagedn 4, up 5, down 6, left 7,
right 8, plus 9, minus 10, model 11, tele 12, sys 13. Event = flag + k, with first = 0x60 (96), break = 0x20 (32),
rept = 0x40 (64), long = 0x80 (128). Examples from the table below.

| key (input-file name) | first | break | long | rept |
|---|---|---|---|---|
| enter | 98 | 34 | 130 | 66 |
| exit | 97 | 33 | 129 | - |
| pageup / pagedn | 99 / 100 | 35 / 36 | - | - |
| up / down / left / right | 101 / 102 / 103 / 104 | 37 / 38 / 39 / 40 | - | - |
| plus / minus (also `next` / `prev`) | 105 / 106 | 41 / 42 | - | - |
| menu | 96 | 32 | - | - |
| model / tele / sys | 107 / 108 / 109 | 43 / 44 / 45 | 139 / 140 / 141 | - |
| `rot_next` / `rot_prev` (rotary step) | 4100 / 4099 | - | - | - |

Named constants (identical on tx12 and boxer): `EVT_ENTER_FIRST`=98, `EVT_ENTER_BREAK`=34, `EVT_ENTER_LONG`=130,
`EVT_ENTER_REPT`=66, `EVT_EXIT_BREAK`=33, `EVT_PAGEUP_FIRST/BREAK`=99/35, `EVT_PAGEDN_FIRST/BREAK`=100/36,
`EVT_ROT_LEFT`=4099, `EVT_ROT_RIGHT`=4100, `EVT_ROT_BREAK`=34 (same as ENTER_BREAK), `EVT_ROT_LONG`=130,
`EVT_ROT_REPT`=66, `EVT_SYS_FIRST/BREAK/LONG`=109/45/141, `EVT_MODEL_*`=107/43/139, `EVT_TELEM_*`=108/44/140,
`EVT_VIRTUAL_ENTER`=34, `EVT_VIRTUAL_EXIT`=33, `EVT_VIRTUAL_NEXT/INC`=4100, `EVT_VIRTUAL_PREV/DEC`=4099,
`EVT_VIRTUAL_MENU`=43, `EVT_VIRTUAL_MENU_LONG`=139, `EVT_VIRTUAL_ENTER_LONG`=130.
Not defined (nil) here: `EVT_EXIT_FIRST/LONG`, `EVT_MENU_*`, `EVT_UP/DOWN/LEFT/RIGHT_BREAK`, `EVT_PLUS/MINUS_*`,
`EVT_PAGE_*`, `EVT_VIRTUAL_MENU_UP/DWN/PGUP/PGDN`. Note `pairs(_G)` does not list the EVT_ constants (lazy
globals); look them up by name. `table` is not available inside tool scripts (error `-E-` in the trace).
* `next`/`prev` on both radios pressed the PLUS/MINUS keys (105/41, 106/42): the DLL reports no rotary
  capability on boxer through this API, so use `rot_next`/`rot_prev` to send real encoder steps: the script
  then receives a single 4100 (right) or 4099 (left) event, with no first/break pair.
  So `EVT_VIRTUAL_NEXT` is delivered by the roller, not by PLUS.
* `killEvents(130)` after a long ENTER does NOT suppress the following events: 66 (rept, twice) and the
  34 break still arrive. EXIT long gives 97 then 129 and no 33 break, with or without `killEvents(129)`.

## Limitations
* Real-time, not tick-exact: the firmware runs on its own threads at wall-clock speed; frames are
  sampled every ~50 ms (Python sleep jitter ~ a few ms) and input timing has the same jitter. Run-to-run
  frame content can differ by a frame or two. A run takes boot (about 5 s) + the scripted duration.
* Tool selection by list position assumes the tools page lists only your SCRIPTS/TOOLS scripts first;
  verified only with a single tool in the SD folder. If several tools exist, check the first frames
  or override with `--nav`.
* No persistent state beyond what the firmware writes into `<out>/_sd`. Audio is disabled (no device).
* Process ends with `os._exit` because the firmware threads do not join cleanly.
* Lua errors are not detected automatically; look at the frames and `firmware_trace.txt`.
