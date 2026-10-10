-- lua5.2 tools/bench.lua [scenario ...]: before/after numbers for speed work. Replays bot scenarios (inputs/*.lua)
-- with the lcd drawing functions swapped for an empty C function (on the radio they are C; the mock's are Lua
-- and would be counted) and counts the Lua instructions and C calls of every frame (game logic + drawing).
-- PROFILE=1 also prints where the instructions go (per function, sampled 1 in 10).
local out = io.stdout
local H = dofile("tools/harness.lua")
local names = { ... }
if #names == 0 then names = { "04_play_start", "06_play_final", "13_scroll", "14_coupled", "16_zen", "perf_worst" } end
local profile = os.getenv("PROFILE") == "1"
local stub = os.clock -- a C function that takes anything
local getinfo, smatch = debug.getinfo, string.match -- (the radio sandbox hides debug and string methods)
local DRAW = { "clear", "drawLine", "drawFilledRectangle", "drawRectangle", "drawPoint", "drawText", "drawNumber" }

local per, ptotal = {}, 0
local tn, tf, tw = 0, 0, 0
for _, name in ipairs(names) do
  local sc = dofile("inputs/" .. name .. ".lua")
  local h = H.new({ sd = "bench", setup = sc.setup, fast = true })
  for _, k in ipairs(DRAW) do rawset(lcd, k, stub) end
  local n, c, sum, csum, worst, frames, playing = 0, 0, 0, 0, 0, 0, 0
  local function hook(ev)
    if ev == "count" then
      n = n + 1
      if profile and n % 10 == 0 then
        local i = getinfo(2, "S")
        local key = (smatch(i.short_src, "([%w_]+%.lua)") or i.short_src) .. ":" .. i.linedefined
        per[key] = (per[key] or 0) + 10
        ptotal = ptotal + 10
      end
    elseif getinfo(2, "S").what == "C" then c = c + 1 end
  end
  for f = 1, sc.frames do
    local a1, a2, a3, a4, a5 = sc.fn(f, h.S.clock + 5, h.ctx)
    n, c = 0, 0
    debug.sethook(hook, "c", 1)
    h.step(a1, a2, a3, a4, a5)
    debug.sethook()
    local st = h.app.state()
    if st >= 6 and st <= 7 or st == 10 then -- PLAY, PAUSE, WRECK: the frames that matter
      sum, csum, frames = sum + n, csum + c, frames + 1
      if n > worst then worst = n end
    end
  end
  out:write(string.format("%-14s play frames %5d  mean %6.0f instr %5.1f C calls  worst %6d instr\n", name, frames,
    sum / math.max(frames, 1), csum / math.max(frames, 1), worst))
  tn, tf, tw = tn + sum / math.max(frames, 1), tf + 1, tw + worst
end
out:write(string.format("ALL           mean of means %6.0f instr   sum of worsts %d\n", tn / tf, tw))
if profile then
  local keys = {}
  for k in pairs(per) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return per[a] > per[b] end)
  for i = 1, math.min(#keys, 20) do
    out:write(string.format("  %-20s %5.1f %%\n", keys[i], 100 * per[keys[i]] / ptotal))
  end
end
