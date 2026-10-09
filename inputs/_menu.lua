-- shared helpers for scenarios: ENTER through warning + title, then centered sticks
local M = {}
-- frames 1..20: warning -> title (10) -> CENTER (20)
function M.arm(f)
  if f == 10 or f == 20 then return 0, 0, 0, 0, "enter" end
  return 0, 0, 0, 0
end
-- frame at which PLAY starts (tick 1) when arm() is used with centered sticks
M.PLAY = 20 + 10 + 61
-- stats file with a best of 1:21 for the default config
function M.best(h)
  local f = h.S.realio.open(h.S.sdroot .. "/SCRIPTS/TOOLS/GATERUSH/gaterush.dat", "wb")
  f:write("m2d3s3a2c2t40 81000 6 38000\n")
  f:close()
end
-- perfect bot after arming
function M.bot(o)
  local Bot = dofile("tools/bot.lua")
  local b = Bot.new(o or {})
  return b
end
return M
