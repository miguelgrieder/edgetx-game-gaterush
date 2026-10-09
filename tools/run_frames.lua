-- lua5.2 tools/run_frames.lua --frames 600 --script inputs/x.lua --out out/x/ [--emoji] [--ascii] [--target src|dist] [--every n]
-- Input script: return function(frame, t, ctx) -> ail, ele, thr, rud, event   (ctx.game etc. only with --target src)
-- or a table { fn = that function, frames = N, target = "src", setup = function(h) end }
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local H = dofile(here .. "harness.lua")

local args = { every = 1 }
local i = 1
while i <= #arg do
  local k = arg[i]:match("^%-%-(.+)$")
  if k == "emoji" or k == "ascii" or k == "nopbm" then args[k] = true; i = i + 1
  elseif k then args[k] = arg[i + 1]; i = i + 2
  else i = i + 1 end
end
assert(args.script and args.out, "usage: run_frames.lua --script inputs/x.lua --out out/x [--frames N]")
local every = tonumber(args.every)
local out = args.out:gsub("[/\\]$", "")
H.mock.mkdirp(out)

local input = dofile(args.script)
local opts = type(input) == "table" and input or { fn = input }
local name = args.script:match("([^/\\]+)%.lua$")
local frames = tonumber(args.frames) or math.max(600, opts.frames or 0) -- at least 600 frames per scenario
local h = H.new({ target = args.target or opts.target or "dist", sd = "frames_" .. name, stickMode = opts.stickMode, modelName = opts.modelName,
  setup = opts.setup })
local realio = h.S.realio

local function write(path, text)
  local f = assert(realio.open(path, "wb"))
  f:write(text)
  f:close()
end

local sumCalls, maxCalls, maxFrame, mem50, memEnd, memMax = 0, 0, 0, nil, nil, 0
local ctx = h.ctx
local ran, nTones, nHaptics = 0, 0, 0
for f = 1, frames do
  local ail, ele, thr, rud, ev = opts.fn(f, h.S.clock + 5, ctx)
  local r = h.step(ail, ele, thr, rud, ev)
  -- move the mock's sound logs out so they do not count as game memory
  nTones, nHaptics = nTones + #h.S.tones, nHaptics + #h.S.haptics
  h.S.tones, h.S.haptics = {}, {}
  ran = f
  local c = h.lastCalls
  sumCalls = sumCalls + c
  if c > maxCalls then maxCalls, maxFrame = c, f end
  if not args.nopbm and f % every == 0 then
    write(string.format("%s/frame_%04d.pbm", out, f), h.S.fb:pbm())
    if args.ascii then write(string.format("%s/frame_%04d.txt", out, f), h.S.fb:ascii()) end
    if args.emoji then write(string.format("%s/frame_%04d.emoji.txt", out, f), h.S.fb:emoji()) end
  end
  if f == 50 or f == frames or f % 50 == 0 then
    collectgarbage("collect")
    local m = collectgarbage("count")
    if f == 50 then mem50 = m end
    if f > 50 and m > memMax then memMax = m end
    memEnd = m
  end
  if r ~= 0 then break end
end

local growth = mem50 and (memMax - mem50) or 0
local metrics = string.format(
  '{\n  "frames": %d,\n  "draw_calls_max": %d,\n  "draw_calls_max_frame": %d,\n  "draw_calls_avg": %.1f,\n'
  .. '  "mem_kb_at_50": %.1f,\n  "mem_kb_end": %.1f,\n  "mem_growth_kb": %.2f,\n  "tones": %d,\n  "haptics": %d,\n'
  .. '  "returned": %d,\n  "time_alive_ms": %s,\n  "crashed": %s\n}\n',
  ran, maxCalls, maxFrame, sumCalls / ran, mem50 or 0, memEnd or 0, growth, nTones, nHaptics, h.ret or 0,
  h.game and h.game.t and tostring(h.game.ms()) or "null", h.game and tostring(h.game.crashed or "null") or "null")
write(out .. "/metrics.json", metrics)
h.S.realio.stdout:write(name, ": ", metrics:gsub("%s+", " "), "\n")
if growth > 2 and ran >= 500 then
  h.S.realio.stderr:write("FAIL: memory grew ", growth, " KB\n")
  os.exit(1)
end
