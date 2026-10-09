local m = dofile("inputs/_menu.lua")
local bot = m.bot()
local P = m.PLAY + 92 * 20 + 5
return { target = "src", frames = P + 10, fn = function(f, t, ctx)
  if f > P then return 0, 0, 0, 0, f == P + 1 and "exit" or nil end
  return bot(f, t, ctx)
end }
