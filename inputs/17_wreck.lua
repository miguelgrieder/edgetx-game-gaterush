-- crash animation: the props fly off the wreck
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
local O = m.PLAY + 200
return { target = "src", setup = m.cfg("SEED=9\n"), frames = O + 16, fn = function(f, t, ctx)
  local a, b, c, d, ev = bot(f, t, ctx)
  if f > O then c, d = -1024, 1024 end
  return a, b, c, d, ev
end }
