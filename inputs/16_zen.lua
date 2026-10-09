-- ZEN: live accuracy top right, no crash
local m = dofile("inputs/_menu.lua")
local bot = m.bot({ delay = 2, noise = 2 })
return { target = "src", setup = m.cfg("MODE=3\nSEED=5\n"), frames = m.PLAY + 400, fn = bot }
