local T = dofile("tests/t.lua")

local function setup()
  local h = T.H.new({ sd = "t_input" })
  h.input.setRange(6)
  return h, h.input
end

T.test("4 stick modes map the right sources to each half", function()
  local h, input = setup()
  h.S.inputs.ail, h.S.inputs.ele, h.S.inputs.thr, h.S.inputs.rud = 100, 200, 300, 400
  local want = {
    { 400, 200, 100, 300 }, -- mode 1: left rud+ele, right ail+thr
    { 400, 300, 100, 200 }, -- mode 2: left rud+thr, right ail+ele
    { 100, 300, 400, 200 }, -- mode 3: left ail+thr, right rud+ele
    { 100, 200, 400, 300 }, -- mode 4: left ail+ele, right rud+thr
  }
  for mode = 1, 4 do
    input.read(mode)
    for i = 1, 4 do T.eq(input.raw[i], want[mode][i], "mode " .. mode .. " axis " .. i) end
  end
end)

T.test("full travel maps exactly onto the usable area, Y inverted", function()
  local h, input = setup()
  local S = h.S.inputs
  S.rud, S.thr = -1024, 1024 -- left stick: full left, full up
  S.ail, S.ele = 1024, -1024 -- right stick: full right, full down
  input.read(2)
  T.eq(input.lx, 8) T.eq(input.ly, 8)
  T.eq(input.rx, 55) T.eq(input.ry, 55)
  S.rud, S.thr = 0, 0
  input.read(2)
  T.near(input.lx, 31.5) T.near(input.ly, 31.5)
end)

T.test("MARGIN changes the mapping range", function()
  local h, input = setup()
  input.setRange(4 + 5)
  h.S.inputs.rud = 1024
  input.read(2)
  T.eq(input.lx, 63 - 9 - 2)
  input.setRange(4)
  input.read(2)
  T.eq(input.lx, 63 - 4 - 2)
end)

T.test("nil and out-of-range stick values are tamed", function()
  local h, input = setup()
  h.S.inputs.rud = nil
  h.S.inputs.thr = 1500
  input.read(2)
  T.eq(input.raw[1], 0)
  T.eq(input.raw[2], 1024)
end)

T.test("centered: +-8 % on both axes of a side", function()
  local h, input = setup()
  local S = h.S.inputs
  S.rud, S.thr, S.ail, S.ele = 82, -82, 83, 0
  input.read(2)
  T.eq(input.centered(1), true)
  T.eq(input.centered(2), false)
end)

T.test("leaving the settings applies the new MARGIN to the stick mapping", function()
  local h = T.H.new({ sd = "t_input_menu" })
  h.wait(10)
  h.step(0, 0, 0, 0) -- (the game opens on the title)
  h.wait(10)
  h.step(0, 0, 0, 0, "long")
  h.step(0, 0, 0, 0, "enter") -- release after the long press is swallowed
  h.wait(10)
  for _ = 1, 5 do h.step(0, 0, 0, 0, "next") end -- PRESET MODE TRACK COUPLE SEED -> MARGIN
  h.step(0, 0, 0, 0, "enter") -- edit MARGIN
  h.step(0, 0, 0, 0, "next")
  h.step(0, 0, 0, 0, "next")
  h.step(0, 0, 0, 0, "enter")
  T.eq(h.config.v.MARGIN, 4)
  T.eq(h.config.v.PRESET, 5) -- CUSTOM once a difficulty value moves off the preset
  h.step(0, 0, 0, 0, "exit")
  T.eq(h.input.lo, 4 + 4 + 2)
end)
