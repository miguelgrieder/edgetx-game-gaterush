-- practice LEFT: one tunnel, the right half rests
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", setup = m.cfg("MODE=4\nSEED=13\n"), frames = m.PLAY + 240, fn = bot }
