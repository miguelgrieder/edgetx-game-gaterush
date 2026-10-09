-- Tunnel: ring buffer of centerline points, head generator, tail fade, outline, distance.
local draw = require("draw")

local M = {}

M.FADE = 9 -- points behind the tail that fade out (3 per dither age)
M.CAP = 80 + M.FADE + 1
M.STEP_PX = 4 -- target spacing of outline vertices
M.MAXV = 45 -- max outline vertices per tunnel (2 lines each)

local cos, sin, floor = math.cos, math.sin, math.floor

-- semicircle offsets for the rounded ends (-90..+90 deg around the heading)
local CA, SA = {}, {}
for i = 0, 8 do
  CA[i] = cos(-math.pi / 2 + i * math.pi / 8)
  SA[i] = sin(-math.pi / 2 + i * math.pi / 8)
end

function M.new()
  local T = { x = {}, y = {}, c = {}, s = {} }
  for i = 1, M.CAP do T.x[i], T.y[i], T.c[i], T.s[i] = 0, 0, 1, 0 end
  return T
end

-- Park-Miller generator, one per tunnel
local function rnd(T)
  T.seed = (T.seed * 16807) % 2147483647
  return T.seed / 2147483647
end
M.rnd = rnd

local function put(T, x, y, h)
  T.head = T.head + 1
  local i = (T.head - 1) % M.CAP + 1
  T.x[i], T.y[i], T.c[i], T.s[i] = x, y, cos(h), sin(h)
  T.hx, T.hy, T.h = x, y, h
end

-- spawn at (x, y): the tail stays here until the tunnel reaches len points
function M.reset(T, x, y, seed, len)
  T.seed = seed % 2147483646 + 1
  T.len = len
  T.head = 0
  T.k = 0
  T.near = 1
  put(T, x, y, rnd(T) * 2 * math.pi)
end

function M.tail(T)
  local t = T.head - T.len + 1
  return t < 1 and 1 or t
end

-- advance the head by v px; kmax = max curvature (1/px); rmin = min turn radius used near walls
function M.step(T, v, kmax, lo, hi, rmin)
  local x, y, h = T.hx, T.hy, T.h
  local k = T.k * 0.85 + (rnd(T) * 2 - 1) * kmax * 0.6
  local ch, sh = cos(h), sin(h)
  local ahead = rmin + 4
  local fx, fy = x + ch * ahead, y + sh * ahead
  if fx < lo or fx > hi or fy < lo or fy > hi then
    -- about to hit the wall: turn hard toward the middle of the area
    local mid = (lo + hi) / 2
    k = (ch * (mid - y) - sh * (mid - x)) >= 0 and 1 / rmin or -1 / rmin
  elseif k > kmax then k = kmax
  elseif k < -kmax then k = -kmax
  end
  T.k = k
  h = h + k * v
  if h > math.pi then h = h - 2 * math.pi elseif h < -math.pi then h = h + 2 * math.pi end
  x, y = x + cos(h) * v, y + sin(h) * v
  if x < lo then x = lo elseif x > hi then x = hi end
  if y < lo then y = lo elseif y > hi then y = hi end
  put(T, x, y, h)
end

-- age of point n: 0 solid, 1..3 fading
local function age(n, tail)
  if n >= tail then return 0 end
  return 1 + floor((tail - 1 - n) / 3)
end

local function cap(T, i, xo, rt, dir, pat)
  local x, y = T.x[i] + xo, T.y[i]
  local c, s = T.c[i] * dir, T.s[i] * dir
  local px, py
  for a = 0, 8 do
    local ox, oy = rt * (c * CA[a] - s * SA[a]), rt * (s * CA[a] + c * SA[a])
    local nx, ny = floor(x + ox + 0.5), floor(y + oy + 0.5)
    if px then draw.line(px, py, nx, ny, pat) end
    px, py = nx, ny
  end
end

-- outline: two offset polylines + rounded ends, fading behind the tail
function M.draw(T, xo, rt, v)
  local tail = M.tail(T)
  local first = tail - M.FADE
  if first < 1 then first = 1 end
  -- ~4 px between vertices, but never more than MAXV vertices (draw-call budget at high speed)
  local stride = floor(M.STEP_PX / v + 0.5)
  local need = math.ceil((T.head - first + 1) / M.MAXV)
  if stride < need then stride = need end
  if stride < 1 then stride = 1 end
  local CAP, X, Y, C, S = M.CAP, T.x, T.y, T.c, T.s
  local lx, ly, rx, ry, pa
  for n = first, T.head do
    if n == first or n == T.head or n % stride == 0 then
      local i = (n - 1) % CAP + 1
      local x, y, ox, oy = X[i] + xo, Y[i], -S[i] * rt, C[i] * rt
      local nlx, nly = floor(x + ox + 0.5), floor(y + oy + 0.5)
      local nrx, nry = floor(x - ox + 0.5), floor(y - oy + 0.5)
      if lx then
        local pat = draw.PAT[pa]
        draw.line(lx, ly, nlx, nly, pat)
        draw.line(rx, ry, nrx, nry, pat)
      end
      lx, ly, rx, ry, pa = nlx, nly, nrx, nry, age(n, tail)
    end
  end
  cap(T, (T.head - 1) % CAP + 1, xo, rt, 1, SOLID)
  local fa = age(first, tail)
  if fa < 4 then cap(T, (first - 1) % CAP + 1, xo, rt, -1, draw.PAT[fa]) end
end

-- squared distance from (qx, qy) to segment n -> n+1; returns d2 and the unclamped projection t
local function seg(T, n, qx, qy)
  local CAP = M.CAP
  local i, j = (n - 1) % CAP + 1, n % CAP + 1
  local ax, ay = T.x[i], T.y[i]
  local dx, dy = T.x[j] - ax, T.y[j] - ay
  local l2 = dx * dx + dy * dy
  local t = 0
  if l2 > 0 then t = ((qx - ax) * dx + (qy - ay) * dy) / l2 end
  local tc = t < 0 and 0 or (t > 1 and 1 or t)
  local ex, ey = ax + dx * tc - qx, ay + dy * tc - qy
  return ex * ex + ey * ey, t
end

local function scan(T, a, b, qx, qy)
  local best, bn, bt = 1e9, a, 0
  for n = a, b do
    local d2, t = seg(T, n, qx, qy)
    if d2 < best then best, bn, bt = d2, n, t end
  end
  return best, bn, bt
end

-- distance check against the solid part (tail..head)
-- returns d2 and true when the tail has just passed the quad (behind the tail point, near it)
function M.near(T, qx, qy, rt2)
  local tail, head = M.tail(T), T.head
  if head == tail then
    local i = (head - 1) % M.CAP + 1
    local ex, ey = T.x[i] - qx, T.y[i] - qy
    return ex * ex + ey * ey, false
  end
  local a, b = T.near - 12, T.near + 12
  if a < tail then a = tail end
  if b > head - 1 then b = head - 1 end
  local d2, n, t
  if a <= b then d2, n, t = scan(T, a, b, qx, qy) end
  -- full scan when the window says "out" or its best is on a window edge (the quad may be past it)
  if not d2 or d2 > rt2 or (n == a and a > tail) or (n == b and b < head - 1) then
    d2, n, t = scan(T, tail, head - 1, qx, qy)
  end
  T.near = n
  -- "tail" only while the quad is still within the rounded end it just slipped off
  return d2, n == tail and t < 0 and d2 <= rt2
end

return M
