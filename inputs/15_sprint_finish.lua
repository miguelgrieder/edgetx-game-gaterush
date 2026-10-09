-- SPRINT: 60 s, then the FINISH screen with accuracy
local m = dofile("inputs/_menu.lua")
local bot = m.bot({ noise = 1 })
return { target = "src", setup = m.cfg("MODE=2\nSEED=3\n"), frames = m.PLAY + 1200 + 8, fn = bot }
