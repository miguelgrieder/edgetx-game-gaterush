local T = dofile("tests/t.lua")

local function setup(o)
  local h = T.H.new(o or { sd = "t_config" })
  return h, h.config, h.menus
end

local function writeSd(h, path, text)
  local f = h.S.realio.open(h.S.sdroot .. path, "wb")
  f:write(text)
  f:close()
end

T.test("defaults and ranges", function()
  local _, c, m = setup()
  c.defaults()
  T.eq(c.v.MARGIN, 2) T.eq(c.v.CRASH_DELAY, 5) T.eq(c.v.SPEED, 4) T.eq(c.v.SPEED_ACCEL, 2)
  T.eq(c.v.CURVE_ACCEL, 5) T.eq(c.v.TRACK_LEN, 25) T.eq(c.v.HAPTIC, 1) T.eq(c.v.STICK_MODE, 2)
  T.eq(c.radius(), 6)
  local it = c.item("TRACK_LEN")
  m.change(it, 1) T.eq(c.v.TRACK_LEN, 30)
  for _ = 1, 30 do m.change(it, 1) end
  T.eq(c.v.TRACK_LEN, 115)
  for _ = 1, 20 do m.change(c.item("MARGIN"), -1) end
  T.eq(c.v.MARGIN, 0)
  T.eq(m.label(c.item("CRASH_DELAY")), "0.5 S")
  c.v.CRASH_DELAY = 50
  T.eq(m.label(c.item("CRASH_DELAY")), "5.0 S")
  c.v.CRASH_DELAY = 20
  T.eq(m.label(c.item("CRASH_DELAY")), "2.0 S")
  T.eq(m.label(c.item("MARGIN")), "0 PX")
  c.v.HAPTIC = 0
  T.eq(m.label(c.item("HAPTIC")), "OFF")
end)

T.test("hash changes with every difficulty setting and only with them", function()
  local _, c, m = setup()
  c.defaults()
  local base = c.hash()
  T.eq(base, "m2d5s4a2c5t25")
  for _, k in ipairs({ "MARGIN", "CRASH_DELAY", "SPEED", "SPEED_ACCEL", "CURVE_ACCEL", "TRACK_LEN" }) do
    m.change(c.item(k), 1)
    T.ok(c.hash() ~= base, k)
    c.defaults()
  end
  m.change(c.item("HAPTIC"), -1)
  m.change(c.item("STICK_MODE"), 1)
  T.eq(c.hash(), base)
end)

T.test("save and load round trip", function()
  local _, c, m = setup()
  c.defaults()
  c.v.MARGIN, c.v.TRACK_LEN, c.v.STICK_MODE = 4, 65, 1
  T.eq(c.save(), true)
  c.defaults()
  c.load()
  T.eq(c.v.MARGIN, 4) T.eq(c.v.TRACK_LEN, 65) T.eq(c.v.STICK_MODE, 1)
end)

T.test("corrupted file: bad lines ignored, defaults kept", function()
  local h, c, m = setup()
  writeSd(h, c.FILE, "garbage\nMARGIN=9\nSPEED=4\nTRACK_LEN=33\nHAPTIC=0\n\0\0zz=1\nCRASH_DELAY=-1\n")
  c.load()
  T.eq(c.v.MARGIN, 2) T.eq(c.v.SPEED, 4) T.eq(c.v.TRACK_LEN, 25) T.eq(c.v.HAPTIC, 0) T.eq(c.v.CRASH_DELAY, 5)
end)

T.test("missing GATERUSH folder: io.open nil, save reports failure and the title says NO SAVE", function()
  local h, c, m = setup({ sd = "t_nosave", noSaveFolder = true })
  T.eq(c.save(), false)
  c.load()
  T.eq(c.v.MARGIN, 2)
  h.wait(10)
  h.step(0, 0, 0, 0, "enter")
  h.wait(10)
  local noSave = T.region(h.fb(), 0, 21, 128, 8)
  local ok = T.H.new({ sd = "t_save" })
  ok.wait(10)
  ok.step(0, 0, 0, 0, "enter")
  ok.wait(10)
  T.ok(noSave ~= T.region(ok.fb(), 0, 21, 128, 8), "subtitle should change to NO SAVE")
end)

T.test("getStickMode (EdgeTX 3.0) seeds the default, the file wins", function()
  local h, c, m = setup({ sd = "t_mode", stickMode = 1 })
  c.defaults()
  T.eq(c.v.STICK_MODE, 1)
  writeSd(h, c.FILE, "STICK_MODE=3\n")
  c.load()
  T.eq(c.v.STICK_MODE, 3)
end)

T.test("presets load their values; editing a value falls back to CUSTOM or the matching preset", function()
  local _, c, m = setup()
  c.defaults()
  T.eq(c.v.PRESET, 2)
  local p = c.item("PRESET")
  m.change(p, -1) -- EASY
  T.eq(c.v.MARGIN, 3) T.eq(c.v.CRASH_DELAY, 10) T.eq(c.v.TRACK_LEN, 35)
  m.change(p, 3) -- PRO
  T.eq(c.v.PRESET, 4) T.eq(c.v.SPEED, 6) T.eq(c.v.CURVE_ACCEL, 8)
  m.change(c.item("SPEED"), 1)
  T.eq(c.v.PRESET, 5)
  m.change(c.item("SPEED"), -1)
  T.eq(c.v.PRESET, 4)
  m.change(p, 1) -- CUSTOM keeps the values
  T.eq(c.v.SPEED, 6)
end)

T.test("mode, scroll and coupling get their own records; skins and seed do not", function()
  local _, c, m = setup()
  c.defaults()
  local base = c.hash()
  c.v.MODE = 2
  T.eq(c.hash(), base .. "M2")
  c.v.TRACK, c.v.COUPLE = 2, 3
  T.eq(c.hash(), base .. "M2SC3")
  c.defaults()
  c.v.SKIN_L, c.v.SKIN_R, c.v.SEED = 5, 6, 42
  T.eq(c.hash(), base)
  T.eq(m.label(c.item("SKIN_R")), "PLUS")
  T.eq(m.label(c.item("SEED")), "42")
  c.v.SEED = 0
  T.eq(m.label(c.item("SEED")), "RANDOM")
end)
