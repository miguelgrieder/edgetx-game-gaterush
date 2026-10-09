-- 1:32 with the perfect bot: faster, curvier
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", frames = m.PLAY + 92 * 20 + 5, fn = bot }
