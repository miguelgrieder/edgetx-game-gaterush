# Tuning

> **Update after the first real-radio test:** the defaults are now CRASH DELAY 0.5 s, SPEED 4, CURVE ACCEL 5,
> TRACK LEN 25 (player's choice), with wider ranges (CRASH DELAY up to 5.0 s, SPEED up to 8, CURVE ACCEL up to 8,
> TRACK LEN up to 120). With these defaults the average bot survives 101 s on average (71–136 s, 10 runs) and the
> perfect bot 5 min. The calibration below was done with the original defaults.

All numbers come from `tools/calibrate.lua` (20 runs per profile, 5 min cap, default config:
MARGIN 2, CRASH_DELAY 0.3, SPEED 3, SPEED_ACCEL 2, CURVE_ACCEL 2, TRACK_LEN 40).

## Bot model (`tools/bot.lua`)

The tunnel is a static trail, so a bot that only lags in time never leaves it. The bot therefore models a
hand: it aims at the centerline point 4 points behind the head, sees it `delay` frames late, follows it with
an exponential lag of gain `1/(1+delay)` per frame (cuts corners like a thumb does) and adds a wandering
error of about `noise` px. The perfect bot (`delay 0, noise 0`) moves exactly on the centerline.

## Final tables (`src/config.lua`)

| | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| `SPEED` head speed, px per 50 ms tick | 0.8 | 1.1 | **1.5** | 2.0 | 2.6 |

| value | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| `SPEED_ACCEL` / `CURVE_ACCEL`, % growth per minute | 0 | 45 | **90** | 135 | 180 | 240 |

- Start curvature limit `K0 = 1/16 px⁻¹` (turn radius 16 px), growing with `CURVE_ACCEL`, capped at a
  radius of `RT+3` so the inner edge never folds; curvature ramps from 0 over the first 3 s (straight start).
- Speed and curvature tables started as the spec's (0/15/30/50/75/100 %); with them even a sloppy bot
  survived 5 minutes, so the acceleration table was multiplied by 3. The speed table is unchanged.

## Results with the final tables

| bot | avg | median | min | max |
|---|---|---|---|---|
| perfect (0 frames, 0 px) | 300 s (cap) | 300 s | 300 s | 300 s |
| precise (2 frames, 1 px) | 300 s (cap) | 300 s | 300 s | 300 s |
| **average (4 frames, 2 px)** | **89.5 s** | 93.5 s | 50.4 s | 128.4 s |
| bad (8 frames, 4 px) | 8.2 s | 7.4 s | 2.2 s | 19.1 s |

Target from the spec: the average bot crashes between 40 and 120 s (19 of 20 runs inside, one at 128 s),
the perfect bot survives 5 minutes.

Scan that led there (average bot, 8–10 runs, `V` = SPEED 3 speed, `A` = ACCEL 2 %/min):

| V | A | avg | median |
|---|---|---|---|
| 1.5 | 30 | 182 s | 165 s |
| 1.8 | 30 | 178 s | 170 s |
| 2.0 | 40 | 117 s | 104 s |
| 1.5 | 60 | 125 s | 111 s |
| 1.7 | 60 | 101 s | 105 s |
| **1.5** | **80–90** | **90 s** | **94 s** |

Reproduce: `lua5.2 tools/calibrate.lua 20 300 0 0 2 1 4 2 8 4` (override with env `V=`, `A=`, `K=`).

## Soak

`lua5.2 tools/soak.lua 100`: the bad bot plays 100 games in a row, re-arming from CRASHED, with full
rendering — 26,011 frames, no runtime error, max 208 draw calls, Lua memory after run 10: 579.6 KB,
after run 100: 579.3 KB.

## What a human has to confirm

The bot is a model; the real feel (is SPEED 3 a good warm-up? is +90 %/min too steep?) must be checked on
the radio. If it is too hard, lower `ACCELS` first, not `SPEEDS`.
