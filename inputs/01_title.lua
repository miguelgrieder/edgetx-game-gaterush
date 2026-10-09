local m = dofile("inputs/_menu.lua")
return { frames = 20, setup = m.best, fn = function(f)
  if f == 10 then return 0, 0, 0, 0, "enter" end
  return 0, 0, 0, 0
end }
