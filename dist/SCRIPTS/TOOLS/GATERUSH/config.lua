-- Settings: ranges, defaults, tuning tables, .cfg persistence, difficulty key.
local M = {}

M.VERSION = "v0.1.2" -- shown on the title screen
M.DIR = "/SCRIPTS/TOOLS/GATERUSH/"
M.FILE = M.DIR .. "gaterush.cfg"

-- head speed in px per 50 ms tick, by SPEED 1..8
M.SPEEDS = { 0.8, 1.1, 1.5, 2.0, 2.6, 3.2, 3.9, 4.7 }
-- growth in % per minute alive, by SPEED_ACCEL / CURVE_ACCEL (index = value + 1)
M.ACCELS = { 0, 45, 90, 135, 180, 240, 300, 380, 480 }

M.PRESETS = { "EASY", "NORMAL", "HARD", "PRO", "CUSTOM" }
M.MODES = { "ENDURO", "SPRINT", "ZEN", "LEFT", "RIGHT" }
M.SKINS = { "DISC", "RING", "XFRM", "PODS", "THIN", "PLUS", "GEM", "BLADE" }

-- CRASH_DELAY is stored in tenths of a second so the value stays an integer.
-- names = labels by value (index = value - lo + 1)
M.ITEMS = {
  { key = "PRESET", name = "PRESET", lo = 1, hi = 5, def = 2, names = M.PRESETS },
  { key = "MODE", name = "MODE", lo = 1, hi = 5, def = 1, names = M.MODES },
  { key = "TRACK", name = "TRACK", lo = 1, hi = 2, def = 1, names = { "FREE", "SCROLL" } },
  { key = "COUPLE", name = "COUPLE", lo = 1, hi = 4, def = 1, names = { "OFF", "MIRROR", "COPY", "INVERT" } },
  { key = "SEED", name = "SEED", lo = 0, hi = 99, def = 0 },
  { key = "MARGIN", name = "MARGIN", lo = 0, hi = 5, def = 2 },
  { key = "CRASH_DELAY", name = "CRASH DELAY", lo = 0, hi = 50, def = 5 },
  { key = "SPEED", name = "SPEED", lo = 1, hi = 8, def = 4 },
  { key = "SPEED_ACCEL", name = "SPEED ACCEL", lo = 0, hi = 5, def = 2 },
  { key = "CURVE_ACCEL", name = "CURVE ACCEL", lo = 0, hi = 8, def = 5 },
  { key = "TRACK_LEN", name = "TRACK LEN", lo = 20, hi = 115, step = 5, def = 25 },
  { key = "SKIN_L", name = "LEFT QUAD", lo = 1, hi = 8, def = 1, names = M.SKINS },
  { key = "SKIN_R", name = "RIGHT QUAD", lo = 1, hi = 8, def = 3, names = M.SKINS },
  { key = "HAPTIC", name = "HAPTIC", lo = 0, hi = 1, def = 1, names = { "OFF", "ON" } },
  { key = "STICK_MODE", name = "STICK MODE", lo = 1, hi = 4, def = 2 },
  { key = "DEBUG", name = "DEBUG", lo = 0, hi = 1, def = 0, names = { "OFF", "ON" } }, -- FPS and Lua KB in play
}

M.v = {}

function M.defaults()
  for i = 1, #M.ITEMS do
    local it = M.ITEMS[i]
    M.v[it.key] = it.def
  end
  -- getStickMode() only exists from EdgeTX 3.0; it only seeds the default
  if getStickMode then
    local ok, mode = pcall(getStickMode)
    if ok and type(mode) == "number" and mode >= 1 and mode <= 4 then M.v.STICK_MODE = mode end
  end
end

function M.item(key)
  for i = 1, #M.ITEMS do
    if M.ITEMS[i].key == key then return M.ITEMS[i] end
  end
end

function M.radius() return 4 + M.v.MARGIN end

-- record key, e.g. m2d5s4a2c5t25 (+ M2 for a mode, S for scroll, C2 for coupled hands)
function M.hash()
  local v = M.v
  return "m" .. v.MARGIN .. "d" .. v.CRASH_DELAY .. "s" .. v.SPEED .. "a" .. v.SPEED_ACCEL
    .. "c" .. v.CURVE_ACCEL .. "t" .. v.TRACK_LEN .. (v.MODE > 1 and "M" .. v.MODE or "")
    .. (v.TRACK > 1 and "S" or "") .. (v.COUPLE > 1 and "C" .. v.COUPLE or "")
end

-- apply "KEY=value" lines; invalid or out-of-range lines are ignored
function M.parse(text)
  for k, val in string.gmatch(text, "([%u_]+)=(%-?%d+)") do
    local it = M.item(k)
    local n = tonumber(val)
    if it and n and n >= it.lo and n <= it.hi and (n - it.lo) % (it.step or 1) == 0 then M.v[k] = n end
  end
end

function M.load()
  M.defaults()
  local f = io.open(M.FILE, "r")
  if not f then return end
  local text = io.read(f, 512)
  io.close(f)
  if text then M.parse(text) end
end

-- returns false when the file can't be written (missing GATERUSH/ folder)
function M.save()
  local f = io.open(M.FILE, "w")
  if not f then return false end
  for i = 1, #M.ITEMS do
    local k = M.ITEMS[i].key
    io.write(f, k, "=", M.v[k], "\n")
  end
  io.close(f)
  return true
end

return M
