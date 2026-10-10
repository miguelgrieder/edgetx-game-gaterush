local m = dofile("inputs/_menu.lua")
return { frames = 20, setup = m.best, fn = function(f)
  return 0, 0, 0, 0
end }
