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
function M.dust(x, y, c, s, rt, xo, xmax, gather)
  for _ = 1, gather and 8 or 5 do
    seed = (seed * 16807) % 2147483647
    local d = rt + 1 + seed % (gather and 2 or 5)
    local a = (seed % 19 - 9) / (gather and 3 or 10) -- spread: -0.9..0.9 rad, -3..3 when gathering
    local ca, sa = math.cos(a), math.sin(a)
    local px = math.floor(x + (c * ca - s * sa) * d + 0.5)
    local py = math.floor(y + (s * ca + c * sa) * d + 0.5)
    if px >= 0 and px <= xmax and py >= 0 and py < LCD_H then lcd.drawPoint(px + xo, py, FORCE) end
  end
end

function M.reseed(n) seed = n % 2147483646 + 1 end

return M
