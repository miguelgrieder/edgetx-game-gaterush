-- left hand leaves the tunnel at ~0:10 and stays out: CRASHED, first run = NEW BEST
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
local O = m.PLAY + 200
return { target = "src", frames = O + 40, fn = function(f, t, ctx)
  local a, b, c, d, ev = bot(f, t, ctx)
  if f > O then c, d = (c > 0 and -1024 or 1024), (d > 0 and -1024 or 1024) end
  return a, b, c, d, ev
end }
