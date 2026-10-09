-- paused, then ENT: frozen game, quads follow the sticks, "2"
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
local P = m.PLAY + 92 * 20 + 5
return { target = "src", frames = P + 40, fn = function(f, t, ctx)
  if f == P + 1 then return 0, 0, 0, 0, "exit" end
  if f == P + 10 then return 0, 0, 0, 0, "enter" end
  if f > P then return 200, -300, 400, -500 end
  return bot(f, t, ctx)
end }
