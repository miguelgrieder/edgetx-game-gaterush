-- STOP maneuver (seed 4, 0:28): the left head has hovered and is now eating its tunnel back
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", setup = m.cfg("SEED=4\n"), frames = 666, fn = bot }
