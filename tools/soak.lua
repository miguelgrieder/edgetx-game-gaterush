-- lua5.2 tools/soak.lua [runs] [target]
-- Bad bot plays `runs` games in a row (re-arming from CRASHED) with full rendering:
-- no runtime error, draw calls <= 300, Lua memory stable between the 10th and the last run.
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local H = dofile(here .. "harness.lua")
local Bot = dofile(here .. "bot.lua")

local out = io.stdout -- before the mock replaces io
local runs = tonumber(arg[1]) or 100
local h = H.new({ sd = "soak", target = arg[2] or "src" })
local ctx = h.ctx
local bot = Bot.new({ delay = 8, noise = 4, seed = 99, rearm = true })

local crashes, f, maxCalls, wasCrashed = 0, 0, 0, false
local mem10, total = nil, 0
while crashes < runs do
  f = f + 1
  h.step(bot(f, 0, ctx))
  h.S.tones, h.S.haptics, h.S.loadModes = {}, {}, {} -- the mock's own logs are not game memory
  if h.lastCalls > maxCalls then maxCalls = h.lastCalls end
  local c = h.game.crashed ~= nil
  if c and not wasCrashed then
    crashes = crashes + 1
    total = total + h.game.ms()
    if crashes == 10 then collectgarbage("collect"); mem10 = collectgarbage("count") end
  end
  wasCrashed = c
end
collectgarbage("collect")
local memEnd = collectgarbage("count")
out:write(string.format("soak: %d runs, %d frames, avg run %.1f s, max draw calls %d, mem after run 10 %.1f KB, end %.1f KB (%+.2f KB)\n",
  runs, f, total / runs / 1000, maxCalls, mem10, memEnd, memEnd - mem10))
if maxCalls > 300 or memEnd - mem10 > 2 then
  out:write("FAIL\n")
  os.exit(1)
end
