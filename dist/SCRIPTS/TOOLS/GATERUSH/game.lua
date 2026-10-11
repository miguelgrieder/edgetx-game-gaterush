-- Play group (loaded only during a run): two tunnels, two quads, out/tolerance rule, gates,
-- accuracy, modes, difficulty ramp, HUD, countdown and pause overlays.
local use = ...
local config = use("config")
local input = use("input")
local track = use("track")
local draw = use("draw")
local fx = use("fx")

local M = {}

M.K0 = 1 / 16 -- max curvature at the start (1/px)
M.PROTECT = 30 -- ticks after GO without "out" (1.5 s)
M.SPRINT = 1200 -- sprint length in ticks (60 s)
M.GATE_MS = 2000 -- score bonus per gate (enduro)
M.CAUSE = { "LEFT HAND", "RIGHT HAND", "TAIL" }

M.tracks = { track.new(), track.new() }
M.qx, M.qy = { 32, 32 }, { 32, 32 }
M.outN = { 0, 0 }
M.outTail = { false, false }
M.on = { true, true } -- sides in play (practice modes use one)

local XO = { 0, 65 } -- screen x offset of each half
local floor = math.floor

-- new run: tunnels at the center of each half, a few straight points ahead
function M.spawn(now)
  local v = config.v
  local mode = v.MODE
  M.rt = config.radius()
  M.limit = floor(v.CRASH_DELAY * 2 + 0.5) -- tenths of s -> 50 ms ticks
  if M.limit < 1 then M.limit = 1 end
  M.v0 = config.SPEEDS[v.SPEED]
  M.sa = config.ACCELS[v.SPEED_ACCEL + 1] / 100
  M.ca = config.ACCELS[v.CURVE_ACCEL + 1] / 100
  M.scroll = v.TRACK == 2 -- int
  M.couple = config.couple() -- (upside down makes no sense when scrolling: INVERT plays as MIRROR)
  M.on[1], M.on[2] = mode ~= 5, mode ~= 4 -- int
  M.canCrash = config.crashes()
  M.seed = v.SEED > 0 and v.SEED or now % 99 + 1 -- random runs still get a seed you can replay
  M.t, M.v, M.gates, M.accSum, M.accN, M.anim = 0, M.v0, 0, 0, 0, 0
  M.crashed, M.finished, M.second = nil, nil, -1
  fx.cool = 0
  fx.haptic = v.HAPTIC == 1 -- int
  draw.prepare(v.SKIN_L, v.SKIN_R)
  local mid = (input.lo + input.hi) / 2
  for side = 1, 2 do
    track.reset(M.tracks[side], mid, mid, M.seed * 7919 + side, v.TRACK_LEN, M.rt, M.scroll)
    M.outN[side], M.outTail[side] = 0, false
  end
  for _ = 1, 5 do M.advance(M.v0, 0, M.rt + 3, 0) end
end

-- step the tunnels in play (the right one copies the left when the hands are coupled)
function M.advance(v, kmax, rmin, tsec)
  local L, R = M.tracks[1], M.tracks[2]
  if M.on[1] then track.step(L, v, kmax, input.lo, input.hi, rmin, tsec) end
  if M.couple then track.copy(R, L, M.couple, input.lo + input.hi)
  elseif M.on[2] then track.step(R, v, kmax, input.lo, input.hi, rmin, tsec) end
end

function M.moveQuads()
  M.qx[1], M.qy[1], M.qx[2], M.qy[2] = input.lx, input.ly, input.rx, input.ry
end

-- one 50 ms simulation step
function M.tick()
  M.t = M.t + 1
  fx.tick()
  local tmin = M.t / 1200
  local v = M.v0 * (1 + M.sa * tmin)
  local ramp = M.t / (2 * M.PROTECT) -- straight at GO, full curvature after 3 s
  if ramp > 1 then ramp = 1 end
  local rmin = M.rt + 3
  local kmax = M.K0 * (1 + M.ca * tmin) * ramp
  if kmax > 1 / rmin then kmax = 1 / rmin end
  M.kmax, M.v = kmax, v
  M.anim = M.anim + v * 0.4 -- prop spin follows the speed
  M.advance(v, kmax, rmin, M.t / 20)
  local anyOut = false
  for side = 1, 2 do
    if M.on[side] then
      local T = M.tracks[side]
      local d2, behind, r = track.near(T, M.qx[side], M.qy[side] + T.cam)
      local out = behind or d2 > r * r
      if M.t > M.PROTECT then
        local a = 1 - math.sqrt(d2) / r
        M.accSum, M.accN = M.accSum + (a > 0 and a or 0), M.accN + 1
      else
        out = false
      end
      if out then
        -- the cause is fixed when the out-episode starts (the tail passing the quad)
        if M.outN[side] == 0 then M.outTail[side] = behind end -- int
        M.outN[side] = M.outN[side] + 1
        anyOut = true
        if M.canCrash and M.outN[side] >= M.limit and not M.crashed then
          M.crashed, M.crashSide = M.outTail[side] and 3 or side, side
        end
      else
        M.outN[side] = 0
      end
      -- gates: pass the gate point while inside; gates eaten by the tail or a reversing head vanish
      local G = T.gates
      for k = #G, 1, -1 do
        local g = G[k]
        local passed = not out and T.near >= g
        if passed or g < T.tail or g > T.head then
          if passed then
            M.gates = M.gates + 1
            fx.beep(1800, 30)
          end
          for j = k, #G do G[j] = G[j + 1] end
        end
      end
    end
  end
  -- the cooldown keeps running after coming back in, so flicking in and out cannot flood audio/haptic
  if anyOut then fx.alarm() end
  if M.t >= M.SPRINT and config.v.MODE == 2 then M.finished = true end -- int
end

function M.ms() return M.t * 50 end
function M.acc() return M.accN > 0 and floor(100 * M.accSum / M.accN + 0.5) or 100 end
-- record score: ms (+ gate bonus) or accuracy % in sprint
function M.score()
  if config.v.MODE == 2 then return M.acc() end -- int
  return M.ms() + M.gates * M.GATE_MS
end

-- digits of n in the 3x5 font ending at x; returns the left x
local function number(n, x, y)
  repeat
    x = x - 4
    draw.glyph(draw.digit3[n % 10], x, y)
    n = floor(n / 10)
  until n == 0 -- int
  return x
end

-- m:ss in the 3x5 font; digits are recomputed only when the second changes
local function timer()
  local s = floor(M.t / 20)
  if config.v.MODE == 2 then s = floor((M.SPRINT - M.t + 19) / 20) end -- sprint counts down
  if s ~= M.second then
    M.second = s
    M.m, M.s10, M.s1 = floor(s / 60), floor(s % 60 / 10), s % 10
  end
  local x = 2
  if M.m >= 10 then
    draw.glyph(draw.digit3[floor(M.m / 10) % 10], x, 2)
    x = x + 4
  end
  draw.glyph(draw.digit3[M.m % 10], x, 2)
  draw.glyph(draw.small[":"], x + 4, 2)
  draw.glyph(draw.digit3[M.s10], x + 8, 2)
  draw.glyph(draw.digit3[M.s1], x + 12, 2)
end

function M.drawWorld()
  lcd.drawLine(64, 0, 64, 63, SOLID, FORCE)
  for side = 1, 2 do
    if M.on[side] then
      local T, xo = M.tracks[side], XO[side]
      track.draw(T, xo, M.v)
      local hy = T.hy - T.cam
      if hy >= 0 then fx.dust(T.hx, hy, math.cos(T.h), math.sin(T.h), track.rad(T, T.head), xo,
        side == 1 and 63 or 62, T.hover) end -- int
    end
  end
end

-- out quads blink between the crash and their own sprite every 2 frames
function M.drawQuads(frame, skip)
  local spin = floor(M.anim) % 2 + 1
  for side = 1, 2 do
    if M.on[side] and side ~= skip then
      local x, y = floor(M.qx[side] + 0.5) + XO[side], floor(M.qy[side] + 0.5)
      if M.outN[side] > 0 and frame % 4 < 2 then draw.quad(x, y, true)
      else draw.skin(side == 1 and config.v.SKIN_L or config.v.SKIN_R, x, y, spin) end -- int
    end
  end
end

-- crash animation step k: the crashed quad as wreck, its four props flying off
function M.drawDebris(k)
  local side = M.crashSide
  M.drawQuads(0, side)
  local qx, qy, xo = floor(M.qx[side] + 0.5), floor(M.qy[side] + 0.5), XO[side]
  draw.quad(qx + xo, qy, true)
  local d = 3 + floor(k * 1.5)
  for sx = -1, 1, 2 do
    for sy = -1, 1, 2 do
      local x, y = qx + sx * d, qy + sy * d
      if x >= 1 and x <= 61 and y >= 1 and y <= 61 then lcd.drawFilledRectangle(x + xo - 1, y - 1, 2, 2, FORCE) end
    end
  end
end

-- "3" "2" "1" in an 18x24 box per half, above or below the quad so it never hides it
function M.count(n)
  for side = 1, 2 do
    if M.on[side] then
      local x = side == 1 and 23 or 88 -- int
      local y = M.qy[side] > 32 and 3 or 38
      lcd.drawFilledRectangle(x, y, 18, 24, ERASE)
      lcd.drawRectangle(x, y, 18, 24, FORCE)
      draw.glyph(draw.big[n], x + 3, y + 2)
    end
  end
end

function M.pause()
  lcd.drawFilledRectangle(14, 20, 100, 24, ERASE)
  lcd.drawRectangle(14, 20, 100, 24, FORCE)
  lcd.drawRectangle(16, 22, 96, 20, FORCE)
  lcd.drawText(64, 24, "PAUSED", CENTER)
  lcd.drawText(64, 34, "ENT:GO RTN:QUIT", CENTER)
end

-- what the result screen needs, as plain values (the play group is unloaded after this)
function M.result(quit)
  return { quit = quit, ms = M.ms(), gates = M.gates, acc = M.acc(), seed = M.seed, score = M.score(),
    cause = M.crashed and M.CAUSE[M.crashed] or "QUIT" }
end

function M.drawHud()
  timer()
  if config.v.MODE == 3 then -- int
    draw.glyph(draw.small["%"], 122, 2)
    number(M.acc(), 122, 2)
  else
    number(M.gates, 126, 2)
  end
  if M.on[1] then lcd.drawText(2, 56, "L", 0) end
  if M.on[2] then lcd.drawText(121, 56, "R", 0) end
  if M.outN[1] > 0 then lcd.drawFilledRectangle(0, 54, 9, 10) end
  if M.outN[2] > 0 then lcd.drawFilledRectangle(119, 54, 9, 10) end
end

return M
