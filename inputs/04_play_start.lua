-- 0:07 with the perfect bot
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", frames = m.PLAY + 140, fn = bot }
