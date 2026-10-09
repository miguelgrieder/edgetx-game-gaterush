-- SCROLL track: the tunnels stream down the screen
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", setup = m.cfg("TRACK=2\nSEED=7\n"), frames = m.PLAY + 300, fn = bot }
