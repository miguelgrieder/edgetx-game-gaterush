-- lua5.2 tools/calibrate.lua [runs] [cap_s] [delay noise ...]
-- Survival time of bot profiles with the current default config (src modules).
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local H = dofile(here .. "harness.lua")
local Bot = dofile(here .. "bot.lua")

-- tuning overrides: V=speed of level 3 (px/tick), A=accel % per minute of level 2, K=start curvature 1/px
local V, A, K = tonumber(os.getenv("V") or ""), tonumber(os.getenv("A") or ""), tonumber(os.getenv("K") or "")
local runs = tonumber(arg[1]) or 10
local cap = (tonumber(arg[2]) or 300) * 20
local profiles = {}
if arg[3] then
  for i = 3, #arg, 2 do profiles[#profiles + 1] = { tonumber(arg[i]), tonumber(arg[i + 1]) } end
else
  profiles = { { 0, 0 }, { 4, 2 }, { 8, 4 } }
end
local out = io.stdout

for _, p in ipairs(profiles) do
  local times, sum = {}, 0
  for r = 1, runs do
    local h = H.new({ sd = "calib", clock = 1000 + r * 7777, fast = true, setup = function(h)
      if V then h.config.SPEEDS[3] = V end
      if A then h.config.ACCELS[3] = A end
      if K then h.game.K0 = K end
    end })
    local ctx = { game = h.game, input = h.input, track = h.track, h = h }
    local bot = Bot.new({ delay = p[1], noise = p[2], seed = r })
    local f = 0
    repeat
      f = f + 1
      local a, b, c, d, ev = bot(f, 0, ctx)
      h.step(a, b, c, d, ev)
    until (h.game.crashed and h.game.t and h.game.t > 0) or (h.game.t or 0) >= cap
    local s = h.game.t / 20
    times[#times + 1] = s
    sum = sum + s
  end
  table.sort(times)
  out:write(string.format("delay=%d noise=%d  avg=%.1fs  median=%.1fs  min=%.1fs  max=%.1fs", p[1], p[2],
    sum / runs, times[math.floor((runs + 1) / 2)], times[1], times[runs]))
  out:write("\n")
end
