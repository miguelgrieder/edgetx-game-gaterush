-- COUPLE=MIRROR: the right tunnel mirrors the left
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", setup = m.cfg("COUPLE=2\nSEED=11\n"), frames = m.PLAY + 300, fn = bot }
