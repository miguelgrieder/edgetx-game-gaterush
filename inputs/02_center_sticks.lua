-- left stick centered and holding (bar half full), right stick still off-center
local m = dofile("inputs/_menu.lua")
return { frames = 25, fn = function(f)
  if f <= 20 then return m.arm(f) end
  return 300, 650, 0, 0 -- ail, ele (right), thr, rud (left)
end }
