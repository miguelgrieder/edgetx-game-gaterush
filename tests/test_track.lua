local T = dofile("tests/t.lua")

local function setup()
  local h = T.H.new({ sd = "t_track" })
  return h, h.track
end

local function headPoint(track, Tr)
  local i = track.idx(Tr.head)
  return Tr.x[i], Tr.y[i]
end

T.test("generator stays confined for 10,000 steps at every margin and speed, all maneuvers", function()
  local _, track = setup()
  local Tr = track.new()
  for rt = 4, 9 do
    local lo, hi = rt + 2, 63 - rt - 2
    track.reset(Tr, 31.5, 31.5, rt * 99, 115, rt, false)
    for i = 1, 10000 do
      local v = 0.8 + (i % 7) * 0.6
      track.step(Tr, v, 1 / (rt + 3), lo, hi, rt + 3, 60)
      local x, y = headPoint(track, Tr)
      if x < lo or x > hi or y < lo or y > hi then error("left the area at step " .. i .. ": " .. x .. "," .. y) end
      T.ok(Tr.head - Tr.tail + 1 <= 115 and Tr.head - Tr.tail + 1 >= 1, "length")
    end
  end
end)

T.test("every maneuver shows up once unlocked, none before", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 5, 40, 6, false)
  local seen = {}
  for _ = 1, 3000 do
    track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 4)
    seen[Tr.man] = true
  end
  for m = 4, 9 do T.ok(not seen[m], "maneuver " .. m .. " before its unlock") end
  for _ = 1, 20000 do
    track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 60)
    seen[Tr.man] = true
  end
  for m = 1, 9 do T.ok(seen[m], "maneuver " .. m .. " never picked") end
end)

T.test("stop: hover (no new point, dust gathers), reverse eats the head back, then branch off", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 9, 40, 6, false)
  for _ = 1, 60 do track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 0) end
  Tr.mt = 0
  -- force the next pick to be STOP
  local pickHead = Tr.head
  Tr.man, Tr.mt, Tr.mp, Tr.m0, Tr.ms = track.STOP, 3, 1, 3, 1
  track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 60)
  T.eq(Tr.head, pickHead) T.eq(Tr.hover, true)
  local maxBack, heads = 0, {}
  for _ = 1, 40 do
    track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 60)
    heads[#heads + 1] = Tr.head
    if pickHead - Tr.head > maxBack then maxBack = pickHead - Tr.head end
  end
  T.ok(maxBack >= 5, "reversed " .. maxBack .. " points")
  T.ok(heads[#heads] > pickHead - maxBack, "moving forward again")
  T.ok(Tr.head - Tr.tail + 1 >= track.MINLEN)
end)

T.test("reverse never eats the tunnel below MINLEN", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 3, 20, 6, false)
  for _ = 1, 40 do track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 0) end
  Tr.man, Tr.mt, Tr.mp, Tr.m0, Tr.ms = track.STOP, 1, 2, 1, 1
  Tr.mt = 50
  for _ = 1, 30 do
    track.step(Tr, 1.5, 1 / 16, 8, 55, 9, 60)
    T.ok(Tr.head - Tr.tail + 1 >= track.MINLEN)
  end
end)

T.test("bursts stretch the step to 1.8x", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 4, 40, 6, false)
  for _ = 1, 10 do track.step(Tr, 1, 0, 8, 55, 9, 0) end
  Tr.man, Tr.mt, Tr.m0, Tr.vm, Tr.k = track.BURST, 10, 10, 1.8, 0
  Tr.h = 0
  Tr.hx, Tr.hy = 20, 30
  track.step(Tr, 1, 0, 8, 55, 9, 60)
  T.near(Tr.hx - 20, 1.8, 1e-9)
end)

T.test("chokes narrow the tunnel and leave one gate in the middle", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 8, 115, 6, false)
  local radii = {}
  for _ = 1, 300 do
    track.step(Tr, 1, 0, 8, 55, 9, 0)
    radii[Tr.head] = true
  end
  T.ok(#Tr.gates >= 2, "gates: " .. #Tr.gates)
  local g
  for k = 1, #Tr.gates do
    if Tr.gates[k] - 2 >= Tr.tail and Tr.gates[k] + 3 <= Tr.head then g = Tr.gates[k] end
  end
  local rad = track.rad
  T.eq(rad(Tr, g), 4) T.eq(rad(Tr, g - 1), 4) T.eq(rad(Tr, g - 2), 5) T.eq(rad(Tr, g + 2), 5) T.eq(rad(Tr, g + 3), 6)
  -- a 4 px radius tunnel never chokes below 3
  track.reset(Tr, 31.5, 31.5, 8, 115, 4, false)
  for _ = 1, 300 do
    track.step(Tr, 1, 0, 6, 57, 7, 0)
    T.ok(track.rad(Tr, Tr.head) >= 3)
  end
end)

T.test("scroll mode: head stays near the top, camera only moves up, x confined", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 2, 30, 6, true)
  local cam = Tr.cam
  for _ = 1, 3000 do
    track.step(Tr, 2, 1 / 16, 8, 55, 9, 60)
    T.ok(Tr.cam <= cam + 1e-9, "camera went down")
    cam = Tr.cam
    T.ok(Tr.hx >= 8 and Tr.hx <= 55)
    local sy = Tr.hy - Tr.cam
    T.ok(sy >= 11.99 and sy <= 64, "head on screen at " .. sy)
  end
  T.ok(Tr.cam < -1000, "scrolled " .. Tr.cam)
end)

T.test("coupled hands: mirror, copy and invert", function()
  local _, track = setup()
  local L, R = track.new(), track.new()
  for mode = 2, 4 do
    track.reset(L, 31.5, 31.5, 6, 40, 6, false)
    track.reset(R, 31.5, 31.5, 99, 40, 6, false)
    track.copy(R, L, mode, 63)
    for _ = 1, 400 do
      track.step(L, 1.5, 1 / 16, 8, 55, 9, 60)
      track.copy(R, L, mode, 63)
      local i = track.idx(L.head)
      local wx = mode == 3 and L.x[i] or 63 - L.x[i]
      local wy = mode == 4 and 63 - L.y[i] or L.y[i]
      T.near(R.x[i], wx, 1e-9) T.near(R.y[i], wy, 1e-9)
      T.eq(R.head, L.head) T.eq(R.tail, L.tail) T.eq(#R.gates, #L.gates)
    end
  end
end)

-- straight horizontal tunnel from x=10 to x=40 at y=30, radius 6
local function straight(track, len)
  local Tr = track.new()
  track.reset(Tr, 10, 30, 1, len or 40, 6, false)
  for n = 1, 31 do
    local i = track.idx(n)
    Tr.x[i], Tr.y[i] = 9 + n, 30
  end
  Tr.head, Tr.hx, Tr.hy, Tr.near, Tr.h = 31, 40, 30, 1, 0
  Tr.tail = math.max(1, 31 - (len or 40) + 1)
  return Tr
end

T.test("point-segment distance and the search window", function()
  local _, track = setup()
  local Tr = straight(track)
  local d2, behind, r = track.near(Tr, 25, 33)
  T.near(d2, 9) T.eq(behind, false) T.eq(r, 6)
  -- quad jumps far along the tunnel: the window misses, the full scan finds it
  d2 = track.near(Tr, 39, 31)
  T.near(d2, 1)
  T.ok(Tr.near >= 29)
  -- beyond the head: distance to the head point (rounded cap)
  d2 = track.near(Tr, 44, 30)
  T.near(d2, 16)
end)

T.test("a choke's smaller radius is what counts", function()
  local _, track = setup()
  local Tr = straight(track)
  Tr.chokes[1] = 16 -- radius 5, 4, 4, 4, 5 around point 16 (x=25)
  local _, _, r = track.near(Tr, 25.5, 35)
  T.eq(r, 4)
end)

T.test("behind the tail point counts as tail", function()
  local _, track = setup()
  local Tr = straight(track, 20) -- tail at n=12 (x=21)
  T.eq(track.tail(Tr), 12)
  local _, behind = track.near(Tr, 19, 30)
  T.eq(behind, true)
  _, behind = track.near(Tr, 23, 30)
  T.eq(behind, false)
end)

T.test("outline renders on-screen for long random runs, free and scroll (mock errors off-screen)", function()
  local _, track = setup()
  local Tr = track.new()
  for rt = 4, 9 do
    for scroll = 0, 1 do
      track.reset(Tr, 31.5, 31.5, rt, 115, rt, scroll == 1)
      for i = 1, 600 do
        local v = 0.8 + (i % 5) * 0.8
        track.step(Tr, v, 1 / (rt + 3), rt + 2, 63 - rt - 2, rt + 3, 60)
        lcd.clear()
        track.draw(Tr, 0, v)
        track.draw(Tr, 65, v)
      end
    end
  end
end)

T.test("outline golden: straight tunnel with fading tail", function()
  local h, track = setup()
  local Tr = straight(track, 20)
  lcd.clear()
  track.draw(Tr, 0, 1)
  local got = T.region(h.fb(), 0, 20, 52, 21)
  T.eq(got, T.read("tests/golden/track_straight.txt"))
end)
