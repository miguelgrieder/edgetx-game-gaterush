-- Feedback (tone/haptic with cooldown) and the dust ahead of the tunnel head.
local M = {}

M.cool = 0 -- ticks until the next out-alarm may play
M.haptic = true

function M.tick()
  if M.cool > 0 then M.cool = M.cool - 1 end
end

-- out of the tunnel: 300 Hz / 50 ms + 40 ms vibration, at most every 250 ms
function M.alarm()
  if M.cool > 0 then return end
  playTone(300, 50, 0, PLAY_NOW)
  if M.haptic then playHaptic(40, 0, PLAY_NOW) end
  M.cool = 5
end

function M.beep(freq, ms)
  playTone(freq, ms, 0, PLAY_NOW)
end

-- 5 specks 1..5 px beyond the head cap, re-scattered every frame; a hovering head pulls
-- 8 specks in tight (the warning before it stops and reverses)
local seed = 1
-- the spread angle takes 19 values (-0.9..0.9 rad, -3..3 when gathering): their cos/sin worked out once
-- (math calls are what costs on the radio; v - v % 1 rounds without one)
local COS, SIN, GCOS, GSIN = {}, {}, {}, {}
for k = 0, 18 do
  COS[k], SIN[k] = math.cos((k - 9) / 10), math.sin((k - 9) / 10)
  GCOS[k], GSIN[k] = math.cos((k - 9) / 3), math.sin((k - 9) / 3)
end
function M.dust(x, y, c, s, rt, xo, xmax, gather)
  local CO, SI = gather and GCOS or COS, gather and GSIN or SIN
  for _ = 1, gather and 8 or 5 do
    seed = (seed * 16807) % 2147483647
    local d = rt + 1 + seed % (gather and 2 or 5)
    local k = seed % 19
    local ca, sa = CO[k], SI[k]
    local px = x + (c * ca - s * sa) * d + 0.5
    local py = y + (s * ca + c * sa) * d + 0.5
    px, py = px - px % 1, py - py % 1
    if px >= 0 and px <= xmax and py >= 0 and py < LCD_H then lcd.drawPoint(px + xo, py, FORCE) end
  end
end


return M
