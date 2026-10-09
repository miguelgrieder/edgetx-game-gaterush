-- hold ENT on the title, select CRASH DELAY and edit it
return { frames = 40, fn = function(f)
  if f == 10 then return 0, 0, 0, 0, "enter" end
  if f == 20 then return 0, 0, 0, 0, "long" end
  if f == 24 then return 0, 0, 0, 0, "enter" end -- release after the long press
  if f == 30 then return 0, 0, 0, 0, "next" end
  if f == 32 then return 0, 0, 0, 0, "enter" end
  return 0, 0, 0, 0
end }
