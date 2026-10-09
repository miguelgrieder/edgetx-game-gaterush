-- page 2 (difficulty), CRASH DELAY selected
return { frames = 50, fn = function(f)
  if f == 10 then return 0, 0, 0, 0, "enter" end
  if f == 20 then return 0, 0, 0, 0, "long" end
  if f == 24 then return 0, 0, 0, 0, "enter" end
  if f >= 30 and f <= 42 and f % 2 == 0 then return 0, 0, 0, 0, "next" end
  return 0, 0, 0, 0
end }
