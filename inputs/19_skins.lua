-- other quads: PLUS on the left, BLADE on the right
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", setup = m.cfg("SKIN_L=6\nSKIN_R=8\nSEED=21\n"), frames = m.PLAY + 160, fn = bot }
