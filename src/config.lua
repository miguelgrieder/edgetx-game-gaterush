-- Settings: ranges, defaults, tuning tables, .cfg persistence, difficulty key.
local M = {}

M.DIR = "/SCRIPTS/TOOLS/GATERUSH/"
M.FILE = M.DIR .. "gaterush.cfg"

-- head speed in px per 50 ms tick, by SPEED 1..5
M.SPEEDS = { 0.8, 1.1, 1.5, 2.0, 2.6, 3.2, 3.9, 4.7 }
-- growth in % per minute alive, by SPEED_ACCEL / CURVE_ACCEL 0..5 (index = value + 1)
M.ACCELS = { 0, 45, 90, 135, 180, 240, 300, 380, 480 }

-- CRASH_DELAY is stored in tenths of a second so the value stays an integer.
-- diff = part of the difficulty key
M.ITEMS = {
  { key = "MARGIN", name = "MARGIN", lo = 0, hi = 5, def = 2, diff = true },
  { key = "CRASH_DELAY", name = "CRASH DELAY", lo = 0, hi = 50, def = 5, diff = true },
  { key = "SPEED", name = "SPEED", lo = 1, hi = 8, def = 4, diff = true },
  { key = "SPEED_ACCEL", name = "SPEED ACCEL", lo = 0, hi = 5, def = 2, diff = true },
  { key = "CURVE_ACCEL", name = "CURVE ACCEL", lo = 0, hi = 8, def = 5, diff = true },
  { key = "TRACK_LEN", name = "TRACK LEN", lo = 20, hi = 120, step = 5, def = 25, diff = true },
  { key = "HAPTIC", name = "HAPTIC", lo = 0, hi = 1, def = 1 },
  { key = "STICK_MODE", name = "STICK MODE", lo = 1, hi = 4, def = 2 },
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

-- step the value of item it by dir (+1/-1), clamped
function M.change(it, dir)
  local nv = M.v[it.key] + dir * (it.step or 1)
  if nv < it.lo then nv = it.lo elseif nv > it.hi then nv = it.hi end
  M.v[it.key] = nv
end

-- text shown in the settings list
function M.label(it)
  local v = M.v[it.key]
  if it.key == "MARGIN" then return v .. " PX" end
  if it.key == "CRASH_DELAY" then return math.floor(v / 10) .. "." .. (v % 10) .. " S" end
  if it.key == "HAPTIC" then return v == 1 and "ON" or "OFF" end
  return tostring(v)
end

function M.radius() return 4 + M.v.MARGIN end

-- difficulty key, e.g. m2d3s3a2c2t40
function M.hash()
  local v = M.v
  return "m" .. v.MARGIN .. "d" .. v.CRASH_DELAY .. "s" .. v.SPEED .. "a" .. v.SPEED_ACCEL
    .. "c" .. v.CURVE_ACCEL .. "t" .. v.TRACK_LEN
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
