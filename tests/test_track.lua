local T = dofile("tests/t.lua")

local function setup()
  local h = T.H.new({ sd = "t_track" })
  return h, h.track
end

T.test("generator stays confined for 10,000 steps at every margin and speed", function()
  local _, track = setup()
  local Tr = track.new()
  for rt = 4, 9 do
    local lo, hi = rt + 2, 63 - rt - 2
    track.reset(Tr, 31.5, 31.5, rt * 99, 80)
    for i = 1, 10000 do
      local v = 0.8 + (i % 7) * 0.6
      track.step(Tr, v, 1 / (rt + 3), lo, hi, rt + 3)
      local j = (Tr.head - 1) % track.CAP + 1
      local x, y = Tr.x[j], Tr.y[j]
      if x < lo or x > hi or y < lo or y > hi then error("left the area at step " .. i .. ": " .. x .. "," .. y) end
    end
  end
end)

T.test("the head does not hug the walls (spends most time away from them)", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 31.5, 31.5, 7, 40)
  local onWall = 0
  for _ = 1, 5000 do
    track.step(Tr, 1.5, 1 / 16, 8, 55, 9)
    if Tr.hx <= 8 or Tr.hx >= 55 or Tr.hy <= 8 or Tr.hy >= 55 then onWall = onWall + 1 end
  end
  T.ok(onWall < 250, "head clamped on the wall " .. onWall .. " of 5000 steps")
end)

T.test("ring buffer: tail parks at spawn until TRACK_LEN points, then follows", function()
  local _, track = setup()
  local Tr = track.new()
  track.reset(Tr, 30, 30, 1, 20)
  T.eq(Tr.head, 1) T.eq(track.tail(Tr), 1)
  for _ = 1, 19 do track.step(Tr, 1, 0, 8, 55, 9) end
  T.eq(Tr.head, 20) T.eq(track.tail(Tr), 1)
  for _ = 1, 200 do track.step(Tr, 1, 0.05, 8, 55, 9) end
  T.eq(Tr.head, 220) T.eq(track.tail(Tr), 201)
  -- the oldest faded point (tail - FADE) is still intact in the ring
  local n = track.tail(Tr) - track.FADE
  local i = (n - 1) % track.CAP + 1
  T.ok(Tr.x[i] >= 8 and Tr.x[i] <= 55)
end)

-- straight horizontal tunnel from x=10 to x=40 at y=30
local function straight(track, len)
  local Tr = track.new()
  track.reset(Tr, 10, 30, 1, len or 40)
  Tr.h = 0
  local CAP = track.CAP
  for n = 1, 31 do
    local i = (n - 1) % CAP + 1
    Tr.x[i], Tr.y[i], Tr.c[i], Tr.s[i] = 9 + n, 30, 1, 0
  end
  Tr.head, Tr.hx, Tr.hy, Tr.near = 31, 40, 30, 1
  return Tr
end

T.test("point-segment distance and the search window", function()
  local _, track = setup()
  local Tr = straight(track)
  local d2, behind = track.near(Tr, 25, 33, 36)
  T.near(d2, 9) T.eq(behind, false)
  T.eq(Tr.near >= 15 and Tr.near <= 16, true)
  -- quad jumps far along the tunnel: the window misses, the full scan finds it
  d2 = track.near(Tr, 39, 31, 36)
  T.near(d2, 1)
  T.ok(Tr.near >= 29)
  -- beyond the head: distance to the head point (rounded cap)
  d2 = track.near(Tr, 44, 30, 36)
  T.near(d2, 16)
end)

T.test("behind the tail point counts as tail", function()
  local _, track = setup()
  local Tr = straight(track, 20) -- tail at n=12 (x=21)
  T.eq(track.tail(Tr), 12)
  local _, behind = track.near(Tr, 19, 30, 36)
  T.eq(behind, true)
  _, behind = track.near(Tr, 23, 30, 36)
  T.eq(behind, false)
end)

T.test("outline renders on-screen for long random runs (mock errors on off-screen pixels)", function()
  local _, track = setup()
  local Tr = track.new()
  for rt = 4, 9 do
    track.reset(Tr, 31.5, 31.5, rt, 80)
    for i = 1, 600 do
      local v = 0.8 + (i % 5) * 0.8
      track.step(Tr, v, 1 / (rt + 3), rt + 2, 63 - rt - 2, rt + 3)
      lcd.clear()
      track.draw(Tr, 0, rt, v)
      track.draw(Tr, 65, rt, v)
    end
  end
end)

T.test("outline golden: straight tunnel with fading tail", function()
  local h, track = setup()
  local Tr = straight(track, 20)
  lcd.clear()
  track.draw(Tr, 0, 6, 1)
  local got = T.region(h.fb(), 0, 20, 52, 21)
  local want = T.read("tests/golden/track_straight.txt")
  if not want then
    local f = h.S.realio.open("tests/golden/track_straight.txt", "wb")
    f:write(got)
    f:close()
    error("golden created, review tests/golden/track_straight.txt and rerun")
  end
  T.eq(got, want)
end)
