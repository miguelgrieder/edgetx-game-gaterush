-- PLAY: two tunnels, two quads, out/tolerance rule, difficulty ramp, HUD.
local config = require("config")
local input = require("input")
local track = require("track")
local draw = require("draw")
local fx = require("fx")

local M = {}

M.K0 = 1 / 16 -- max curvature at the start (1/px)
M.PROTECT = 30 -- ticks after GO without "out" (1.5 s)
M.CAUSE = { "LEFT HAND", "RIGHT HAND", "TAIL" }

M.tracks = { track.new(), track.new() }
M.qx, M.qy = { 32, 32 }, { 32, 32 }
M.outN = { 0, 0 }
M.outTail = { false, false }

local XO = { 0, 65 } -- screen x offset of each half
local floor = math.floor

-- new run: tunnels at the center of each half, a few straight points ahead
function M.spawn(seed)
  local v = config.v
  M.rt = config.radius()
  M.rt2 = M.rt * M.rt
  M.limit = floor(v.CRASH_DELAY * 2 + 0.5) -- tenths of s -> 50 ms ticks
  if M.limit < 1 then M.limit = 1 end
  M.v0 = config.SPEEDS[v.SPEED]
  M.sa = config.ACCELS[v.SPEED_ACCEL + 1] / 100
  M.ca = config.ACCELS[v.CURVE_ACCEL + 1] / 100
  M.t = 0
  M.v = M.v0
  M.crashed = nil
  M.second = -1
  fx.cool = 0
  fx.haptic = v.HAPTIC == 1
  local mid = (input.lo + input.hi) / 2
  for side = 1, 2 do
    local T = M.tracks[side]
    track.reset(T, mid, mid, seed + side * 1000003, v.TRACK_LEN)
    for _ = 1, 5 do track.step(T, M.v0, 0, input.lo, input.hi, M.rt + 3) end
    M.outN[side] = 0
    M.outTail[side] = false
  end
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
  M.kmax = kmax
  M.v = v
  local anyOut = false
  for side = 1, 2 do
    local T = M.tracks[side]
    track.step(T, v, kmax, input.lo, input.hi, rmin)
    local d2, behind = track.near(T, M.qx[side], M.qy[side], M.rt2)
    if M.t > M.PROTECT and (behind or d2 > M.rt2) then
      -- the cause is fixed when the out-episode starts (the tail passing the quad)
      if M.outN[side] == 0 then M.outTail[side] = behind end
      M.outN[side] = M.outN[side] + 1
      anyOut = true
      if M.outN[side] >= M.limit and not M.crashed then
        M.crashed = M.outTail[side] and 3 or side
      end
    else
      M.outN[side] = 0
    end
  end
  if anyOut then fx.alarm() else fx.cool = 0 end
end

function M.ms() return M.t * 50 end

-- m:ss in the 3x5 font; digits are recomputed only when the second changes
local function timer()
  local s = floor(M.t / 20)
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
  local rt = M.rt
  for side = 1, 2 do
    local T, xo = M.tracks[side], XO[side]
    track.draw(T, xo, rt, M.v)
    fx.dust(T.hx, T.hy, math.cos(T.h), math.sin(T.h), rt, xo, side == 1 and 63 or 62)
  end
end

-- out quads blink between the crash and the normal sprite every 2 frames
function M.drawQuads(frame)
  for side = 1, 2 do
    local out = M.outN[side] > 0
    draw.quad(floor(M.qx[side] + 0.5) + XO[side], floor(M.qy[side] + 0.5), out and frame % 4 < 2)
  end
end

function M.drawHud()
  timer()
  lcd.drawText(2, 56, "L", 0)
  lcd.drawText(121, 56, "R", 0)
  local n = M.outN[1] > M.outN[2] and M.outN[1] or M.outN[2]
  if n > 0 and M.limit > 1 then
    lcd.drawRectangle(2, 8, 30, 3, FORCE)
    local w = floor(30 * (M.limit - n) / M.limit + 0.5)
    if w > 0 then lcd.drawFilledRectangle(2, 8, w, 3, FORCE) end
  end
  if M.outN[1] > 0 then lcd.drawFilledRectangle(0, 54, 9, 10) end
  if M.outN[2] > 0 then lcd.drawFilledRectangle(119, 54, 9, 10) end
end

return M
