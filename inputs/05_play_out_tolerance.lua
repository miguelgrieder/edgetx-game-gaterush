-- 0:12, the left quad pushed out of the tunnel for 2 frames: tolerance bar, inverted L, crash sprite
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
local N = m.PLAY + 240
return { target = "src", frames = N, fn = function(f, t, ctx)
  local a, b, c, d, ev = bot(f, t, ctx)
  if f > N - 2 then c, d = -1024, 1024 end -- left stick to the bottom-right corner
  return a, b, c, d, ev
end }
