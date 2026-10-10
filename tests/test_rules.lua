local T = dofile("tests/t.lua")

-- game module driven directly, tick by tick
local function setup(cfg)
  local h = T.H.new({ sd = "t_rules" })
  h.config.defaults()
  for k, v in pairs(cfg or {}) do h.config.v[k] = v end
  h.input.setRange(h.config.radius())
  h.game.spawn(12345)
  return h, h.game
end

-- put both quads on the centerline 2 points behind the head, plus an offset (px, along the normal) for side 1
local function follow(h, g, off)
  for side = 1, 2 do
    local Tr = g.tracks[side]
    local i, a, b = h.track.idx(Tr.head - 2), h.track.idx(Tr.head - 3), h.track.idx(Tr.head - 1)
    local dx, dy = Tr.x[b] - Tr.x[a], Tr.y[b] - Tr.y[a]
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1e-9 then dx, dy, l = 1, 0, 1 end
    local o = side == 1 and (off or 0) or 0
    g.qx[side] = Tr.x[i] - dy / l * o
    g.qy[side] = Tr.y[i] + dx / l * o
  end
end

local function run(h, g, n, off)
  for _ = 1, n do
    follow(h, g, off)
    g.tick()
    if g.crashed then return end
  end
end

T.test("inside the tunnel: never out while following the centerline", function()
  local h, g = setup()
  run(h, g, 1200)
  T.eq(g.crashed, nil)
  T.eq(g.outN[1], 0)
end)

T.test("out is decided by the quad center: RT inside, RT+1 out", function()
  local h, g = setup()
  run(h, g, 40)
  run(h, g, 3, 5.5)
  T.eq(g.outN[1], 0)
  run(h, g, 1, 7.5)
  T.eq(g.outN[1], 1)
end)

T.test("CRASH_DELAY=0 kills on the first frame out", function()
  local h, g = setup({ CRASH_DELAY = 0 })
  run(h, g, 40)
  run(h, g, 1, 9)
  T.eq(g.crashed, 1)
end)

T.test("CRASH_DELAY=0.3 tolerates 5 frames, kills on the 6th; coming back resets", function()
  local h, g = setup({ CRASH_DELAY = 3 })
  run(h, g, 40)
  run(h, g, 5, 9)
  T.eq(g.crashed, nil)
  T.eq(g.outN[1], 5)
  run(h, g, 1, 0)
  T.eq(g.outN[1], 0)
  run(h, g, 5, 9)
  T.eq(g.crashed, nil)
  run(h, g, 1, 9)
  T.eq(g.crashed, 1)
  T.eq(g.CAUSE[g.crashed], "LEFT HAND")
end)

T.test("the tail catching the quad is a TAIL crash", function()
  local h, g = setup({ TRACK_LEN = 40 }) -- tail starts moving after the 1.5 s protection
  local side2 = g.tracks[2]
  for _ = 1, 200 do
    follow(h, g, 0)
    g.qx[2], g.qy[2] = side2.x[1], side2.y[1] -- right quad parked at the spawn point
    g.tick()
    if g.crashed then break end
  end
  T.eq(g.crashed, 3)
  T.eq(g.CAUSE[3], "TAIL")
end)

T.test("protected start: no out during the first 1.5 s", function()
  local _, g = setup({ CRASH_DELAY = 0 })
  for _ = 1, 30 do
    g.qx[1], g.qy[1] = 8, 8
    g.tick()
  end
  T.eq(g.crashed, nil)
  g.tick()
  T.eq(g.crashed ~= nil, true)
end)

T.test("speed and curvature ramp with time alive", function()
  local h, g = setup({ SPEED = 3, SPEED_ACCEL = 2, CURVE_ACCEL = 0 })
  run(h, g, 1200)
  T.near(g.v, 1.5 * (1 + h.config.ACCELS[3] / 100), 1e-9)
  T.near(g.kmax, g.K0, 1e-9)
  h, g = setup({ SPEED = 3, SPEED_ACCEL = 0, CURVE_ACCEL = 1 })
  run(h, g, 600)
  T.near(g.v, 1.5, 1e-9)
  T.near(g.kmax, math.min(g.K0 * (1 + h.config.ACCELS[2] / 100 / 2), 1 / 9), 1e-9)
end)

-- full app: menus -> CENTER -> countdown -> PLAY
local function toPlay(o)
  local h = T.H.new(o or { sd = "t_rules_app" })
  h.wait(19)
  h.step(0, 0, 0, 0, "enter")
  for _ = 1, 100 do
    h.step()
    if h.game.t and h.game.t > 0 then break end
  end
  T.eq(h.game.t, 1)
  return h
end

T.test("countdown beeps 3-2-1-GO, then PLAY", function()
  local h = toPlay()
  local tones = h.S.tones
  T.eq(#tones, 4)
  T.eq(tones[2].t - tones[1].t, 100) T.eq(tones[4].f, 1200)
end)

T.test("out feedback: 300 Hz tone + 40 ms haptic every 250 ms, haptic obeys HAPTIC", function()
  local h = toPlay()
  h.config.v.CRASH_DELAY = 20
  h.game.limit = 40
  local n0 = #h.S.tones
  for _ = 1, 60 do h.step(1024, 1024, 1024, 1024) end -- sticks in the corners: out after the protection
  local t = {}
  for i = n0 + 1, #h.S.tones do t[#t + 1] = h.S.tones[i] end
  T.ok(#t >= 4, "tones: " .. #t)
  for i = 2, #t do T.eq(t[i].t - t[i - 1].t, 25) T.eq(t[i].f, 300) T.eq(t[i].d, 50) end
  T.eq(#h.S.haptics, #t)
  T.eq(h.S.haptics[1].d, 40)
  h = toPlay({ sd = "t_rules_nohaptic", setup = function(x) x.config.v.HAPTIC = 0 end })
  h.config.v.HAPTIC = 0
  h.game.limit = 40
  h.game.spawn(1)
  h.game.t = 31
  for _ = 1, 20 do h.step(1024, 1024, 1024, 1024) end
  T.eq(#h.S.haptics, 0)
end)

T.test("pause freezes the game; resume countdown moves only the quads; RTN quits without a record", function()
  local h = toPlay()
  h.wait(10)
  h.step(0, 0, 0, 0, "exit")
  local head, t = h.game.tracks[1].head, h.game.t
  h.wait(40, 500, 500, 500, 500)
  T.eq(h.game.tracks[1].head, head)
  T.eq(h.game.t, t)
  h.step(0, 0, 0, 0, "enter") -- resume countdown
  h.wait(30, -600, 300, 300, -600)
  T.eq(h.game.tracks[1].head, head)
  T.near(h.game.qx[1], h.input.pos(-600))
  h.wait(40)
  T.ok(h.game.t > t, "running again")
  h.step(0, 0, 0, 0, "exit")
  h.wait(10)
  h.step(0, 0, 0, 0, "exit") -- quit from pause
  T.eq(h.stats.best(h.config.hash()), nil)
end)

T.test("crash records the run; a better run is a NEW BEST", function()
  local h = toPlay()
  h.wait(80, 1024, 1024, 1024, 1024)
  T.eq(h.app.state(), 9) -- result screen
  local key = h.config.hash()
  T.ok(h.stats.best(key) > 0)
  T.eq(h.stats.rec[key][2], 1)
  T.eq(h.menus.res.newBest, true)
end)

T.test("gates: passing the gate point inside scores, gates behind the tail vanish", function()
  local h, g = setup({ TRACK_LEN = 60 })
  local passed = 0
  for _ = 1, 600 do
    follow(h, g, 0)
    g.tick()
    passed = g.gates
  end
  T.ok(passed >= 4, "gates passed " .. passed)
  T.eq(g.score(), g.ms() + passed * g.GATE_MS)
  -- a quad parked far away passes nothing (and CRASH_DELAY high so it lives)
  h, g = setup({ CRASH_DELAY = 50 })
  g.limit = 100000
  for _ = 1, 600 do
    g.qx[1], g.qy[1], g.qx[2], g.qy[2] = 8, 8, 8, 8
    g.tick()
  end
  T.eq(g.gates, 0)
  T.eq(#g.tracks[1].gates <= 3, true)
end)

T.test("accuracy: 100 % on the centerline, lower when offset", function()
  local h, g = setup()
  run(h, g, 300)
  T.eq(g.acc(), 100)
  h, g = setup()
  run(h, g, 40)
  run(h, g, 200, 3)
  T.ok(g.acc() < 90 and g.acc() > 40, "acc " .. g.acc())
end)

T.test("sprint: never crashes, finishes at 60 s, scores accuracy", function()
  local h, g = setup({ MODE = 2, CRASH_DELAY = 0 })
  for _ = 1, 1200 do
    g.qx[1], g.qy[1] = 8, 8
    g.tick()
  end
  T.eq(g.crashed, nil)
  T.eq(g.finished, true)
  T.eq(g.score(), g.acc())
end)

T.test("zen never crashes and never finishes", function()
  local _, g = setup({ MODE = 3, CRASH_DELAY = 0 })
  for _ = 1, 2000 do
    g.qx[1], g.qy[1] = 8, 8
    g.tick()
  end
  T.eq(g.crashed, nil) T.eq(g.finished, nil)
end)

T.test("practice LEFT: only the left tunnel runs and only the left hand can crash", function()
  local h, g = setup({ MODE = 4, CRASH_DELAY = 0 })
  local head2 = g.tracks[2].head
  for _ = 1, 200 do
    follow(h, g, 0)
    g.qx[2], g.qy[2] = 8, 8
    g.tick()
  end
  T.eq(g.crashed, nil)
  T.eq(g.tracks[2].head, head2)
  run(h, g, 1, 12)
  T.eq(g.crashed, 1)
end)

T.test("coupled hands: the right tunnel follows the left", function()
  local h, g = setup({ COUPLE = 2 })
  run(h, g, 300)
  local L, R = g.tracks[1], g.tracks[2]
  local i = h.track.idx(L.head)
  T.near(R.x[i], h.input.lo + h.input.hi - L.x[i], 1e-9)
  T.near(R.y[i], L.y[i], 1e-9)
end)

T.test("the same seed flies the same tunnels", function()
  local h, g = setup({ SEED = 42 })
  run(h, g, 300)
  local x1 = g.tracks[1].hx
  h, g = setup({ SEED = 42 })
  run(h, g, 300)
  T.near(g.tracks[1].hx, x1, 1e-9)
  T.eq(g.seed, 42)
end)

T.test("a crash plays the wreck animation, then the result screen records the score", function()
  local h = toPlay()
  local states = {}
  for _ = 1, 60 do
    h.step(1024, 1024, 1024, 1024)
    states[h.app.state()] = true
  end
  T.ok(states[10], "went through the wreck animation")
  T.eq(h.app.state(), 9)
  T.ok(h.stats.best(h.config.hash()) > 0)
end)
