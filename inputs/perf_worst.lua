-- worst case for draw calls: TRACK_LEN 80, MARGIN 5, ~1:30 into a run (perfect bot), then out + HUD
local m = dofile("inputs/_menu.lua")
local bot = m.bot()
return { target = "src", frames = m.PLAY + 95 * 20, setup = function(h)
  local f = h.S.realio.open(h.S.sdroot .. "/SCRIPTS/TOOLS/GATERUSH/gaterush.cfg", "wb")
  f:write("MARGIN=5\nTRACK_LEN=80\nCRASH_DELAY=20\n")
  f:close()
end, fn = function(f, t, ctx)
  local a, b, c, d, ev = bot(f, t, ctx)
  if f % 200 > 190 then a, b, c, d = 1024, 1024, -1024, -1024 end -- both quads out now and then (crash sprites + bar)
  return a, b, c, d, ev
end }
