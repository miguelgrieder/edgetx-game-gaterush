-- Stick reading: STICK_MODE mapping and full travel -> usable area of each half.
local M = {}

-- {left X, left Y, right X, right Y} per stick mode 1..4
M.MAP = {
  { "rud", "ele", "ail", "thr" },
  { "rud", "thr", "ail", "ele" },
  { "ail", "thr", "rud", "ele" },
  { "ail", "ele", "rud", "thr" },
}

M.raw = { 0, 0, 0, 0 } -- -1024..1024, same order as MAP
M.lo, M.hi = 8, 55

-- usable area [RT+2, 63-RT-2]; call again whenever MARGIN changes
function M.setRange(rt)
  M.lo = rt + 2
  M.hi = 63 - rt - 2
end

-- stick value -> half-local coordinate; Y is inverted (stick up = screen up)
function M.pos(v, invert)
  if invert then v = -v end
  return M.lo + (v + 1024) * (M.hi - M.lo) / 2048
end

function M.read(mode)
  local map = M.MAP[mode] or M.MAP[2]
  local raw = M.raw
  for i = 1, 4 do
    local v = getValue(map[i]) or 0
    if v > 1024 then v = 1024 elseif v < -1024 then v = -1024 end
    raw[i] = v
  end
  M.lx, M.ly = M.pos(raw[1]), M.pos(raw[2], true)
  M.rx, M.ry = M.pos(raw[3]), M.pos(raw[4], true)
end

-- side 1 = left, 2 = right: both axes within +-8 %
function M.centered(side)
  local a, b = M.raw[side * 2 - 1], M.raw[side * 2]
  return a <= 82 and a >= -82 and b <= 82 and b >= -82
end

return M
