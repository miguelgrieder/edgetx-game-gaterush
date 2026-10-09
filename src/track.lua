-- Tunnel: ring buffer of centerline points (positions only: directions and choke radii are derived
-- when needed, to save memory), maneuver-driven head with stop/reverse and bursts, chokes with gate
-- posts, fading tail, outline, distance. Coordinates are half-local; in scroll mode y is a world
-- coordinate and T.cam is subtracted when drawing.
local use = ...
local draw = use("draw")

local M = {}

M.FADE = 9 -- points behind the tail that fade out (3 per dither age)
M.CAP = 128 -- >= longest TRACK_LEN (115) + fade + 1; a power of two so the Lua arrays are not oversized
M.STEP_PX = 4 -- target spacing of outline vertices
M.MAXV = 38 -- max outline vertices per tunnel (2 lines each)
M.MINLEN = 8 -- a reversing head never eats the tunnel below this many points

local cos, sin, floor, pi, sqrt = math.cos, math.sin, math.floor, math.pi, math.sqrt

-- maneuvers, in unlock order; UNLOCK = seconds alive before it can be picked
local STRAIGHT, CURVE, ESS, SLALOM, ZIGZAG, BURST, HAIRPIN, STOP, SPIRAL = 1, 2, 3, 4, 5, 6, 7, 8, 9
M.STOP, M.BURST = STOP, BURST
M.UNLOCK = { 0, 0, 0, 5, 10, 15, 20, 25, 30 }
M.CHOKE = { 1, 2, 2, 2, 1 } -- radius reduction along a choke; the 3rd point is the gate

-- semicircle offsets for the rounded ends (-90..+90 deg around the heading)
local CA, SA = {}, {}
for i = 0, 8 do
  CA[i] = cos(-pi / 2 + i * pi / 8)
  SA[i] = sin(-pi / 2 + i * pi / 8)
end

function M.new()
  local T = { x = {}, y = {}, gates = {}, chokes = {} }
  for i = 1, M.CAP do T.x[i], T.y[i] = 0, 0 end
  return T
end

-- Park-Miller generator, one per tunnel
local function rnd(T)
  T.seed = (T.seed * 16807) % 2147483647
  return T.seed / 2147483647
end

local function idx(n) return (n - 1) % M.CAP + 1 end
M.idx = idx

-- tunnel radius at point n (narrower around choke centers)
local function rad(T, n)
  local C, r = T.chokes, T.rt
  for k = 1, #C do
    local d = n - C[k]
    if d >= -2 and d <= 2 then
      local cut = M.CHOKE[d + 3]
      if cut > r - 3 then cut = r - 3 end
      return r - cut
    end
  end
  return r
end
M.rad = rad

-- unit direction of the centerline at point n (from its neighbours inside a..b)
local function dir(T, n, a, b)
  local p, q = n > a and n - 1 or n, n < b and n + 1 or n
  local i, j = idx(p), idx(q)
  local dx, dy = T.x[j] - T.x[i], T.y[j] - T.y[i]
  local l = sqrt(dx * dx + dy * dy)
  if l < 1e-6 then return cos(T.h), sin(T.h) end
  return dx / l, dy / l
end

local function put(T, x, y, h)
  T.head = T.head + 1
  if T.head - T.tail + 1 > T.len then T.tail = T.tail + 1 end
  local i = idx(T.head)
  T.x[i], T.y[i] = x, y
  T.hx, T.hy, T.h = x, y, h
end

local function clear(t)
  for k = #t, 1, -1 do t[k] = nil end
end

-- spawn at (x, y): the tail stays here until the tunnel reaches len points
function M.reset(T, x, y, seed, len, rt, scroll)
  T.seed = seed % 2147483646 + 1
  T.len, T.rt, T.scroll = len, rt, scroll
  T.head, T.tail, T.k, T.near, T.cam = 0, 1, 0, 1, 0
  T.man, T.mt, T.m0, T.vm = STRAIGHT, 30, 30, 1 -- straight start
  T.gt, T.gc = 50 + floor(rnd(T) * 40), 0 -- ticks to the next choke, points left in the current one
  T.hover, T.newGate = false, nil
  clear(T.gates)
  clear(T.chokes)
  put(T, x, y, scroll and -pi / 2 or rnd(T) * 2 * pi)
end

function M.tail(T) return T.tail end

-- choose the next maneuver among those unlocked at tsec seconds alive
local function pick(T, tsec, kmax)
  local n = 0
  for m = 1, #M.UNLOCK do if tsec >= M.UNLOCK[m] then n = m end end
  local m = 1 + floor(rnd(T) * n)
  local sg = rnd(T) < 0.5 and -1 or 1
  local mt = 12 + floor(rnd(T) * 16)
  T.vm, T.mp, T.mk = 1, 0, sg * kmax * (0.6 + 0.4 * rnd(T))
  if m == SLALOM or m == ZIGZAG or m == SPIRAL then mt = mt + 16
  elseif m == HAIRPIN then mt = 60
  elseif m == BURST then T.vm = 1.8
  elseif m == STOP then
    mt, T.mp = 10 + floor(rnd(T) * 6), 1
    -- a choke still ahead of the head is cancelled
    local C = T.chokes
    if T.gc > 0 and C[#C] and C[#C] > T.head then C[#C] = nil end
    T.gc = 0
  end
  T.man, T.ms, T.mt, T.m0 = m, sg, mt, mt
end

-- curvature asked by the current maneuver (1/px)
local function bend(T, v, kmax, rmin)
  local m, sg, t = T.man, T.ms, T.mt
  if m == CURVE then return T.mk end
  if m == ESS then return t * 2 > T.m0 and T.mk or -T.mk end
  if m == SLALOM then return sg * kmax * sin(t * 0.35) end
  if m == ZIGZAG then return t % 8 < 3 and (floor(t / 8) % 2 == 0 and sg or -sg) / rmin or 0 end
  if m == SPIRAL then return sg * (kmax + (1 / rmin - kmax) * (1 - t / T.m0)) end
  if m == HAIRPIN then
    T.mp = T.mp + v / rmin -- turned angle
    if T.mp >= pi then T.mt = 0 end
    return sg / rmin
  end
  return T.k * 0.5 -- straight / burst
end

-- STOP: hover, reverse (the head eats its tunnel back), hover, then branch off; true = no new point
local function stop(T)
  T.mt = T.mt - 1
  if T.mp == 2 then
    if T.mt >= 0 and T.head - T.tail + 1 > M.MINLEN then
      T.head = T.head - 1
      local i, j = idx(T.head), idx(T.head - 1)
      T.hx, T.hy = T.x[i], T.y[i]
      if T.head > T.tail then T.h = math.atan2(T.y[i] - T.y[j], T.x[i] - T.x[j]) end
      local C = T.chokes
      if C[#C] and C[#C] > T.head then C[#C] = nil end
      return true
    end
    T.mp, T.mt = 3, 4
  end
  T.hover = true
  if T.mt > 0 then return true end
  if T.mp == 1 then
    T.mp, T.mt = 2, 6 + floor(rnd(T) * 10)
    return true
  end
  -- branch away from the tunnel it just ate
  T.h = T.h + T.ms * (T.scroll and pi / 4 or pi / 2 + rnd(T) * pi / 4)
  T.man, T.mt, T.m0, T.hover = STRAIGHT, 8, 8, false
  return false
end

-- advance one tick: v = head speed (px), kmax = curvature limit, tsec = seconds alive
function M.step(T, v, kmax, lo, hi, rmin, tsec)
  T.hover, T.newGate = false, nil
  if T.mt <= 0 then pick(T, tsec or 0, kmax) end
  if T.man == STOP and stop(T) then return end
  T.mt = T.mt - 1
  local x, y, h = T.hx, T.hy, T.h
  v = v * T.vm
  local k = bend(T, v, kmax, rmin)
  local ch, sh = cos(h), sin(h)
  local ahead = rmin + 4
  local fx, fy = x + ch * ahead, y + sh * ahead
  if T.scroll then
    -- keep heading up (within ~57 deg), away from the side walls
    local d = (h + pi / 2 + pi) % (2 * pi) - pi -- angle away from straight up
    if fx < lo or d < -1 then k = 1 / rmin elseif fx > hi or d > 1 then k = -1 / rmin end
  elseif fx < lo or fx > hi or fy < lo or fy > hi then
    -- about to hit the wall: turn hard toward the middle of the area
    local mid = (lo + hi) / 2
    k = (ch * (mid - y) - sh * (mid - x)) >= 0 and 1 / rmin or -1 / rmin
  end
  if k > 1 / rmin then k = 1 / rmin elseif k < -1 / rmin then k = -1 / rmin end
  T.k = k
  h = h + k * v
  if h > pi then h = h - 2 * pi elseif h < -pi then h = h + 2 * pi end
  x, y = x + cos(h) * v, y + sin(h) * v
  if x < lo then x = lo elseif x > hi then x = hi end
  if T.scroll then
    if y - T.cam < lo + 4 then T.cam = y - lo - 4 end
  elseif y < lo then y = lo elseif y > hi then y = hi end
  -- chokes: every few seconds the next 5 points narrow, the middle one is a gate
  local C = T.chokes
  if T.gc == 0 then
    T.gt = T.gt - 1
    if T.gt <= 0 and T.man ~= STOP then
      T.gc, T.gt = 5, 60 + floor(rnd(T) * 40)
      C[#C + 1] = T.head + 3
    end
  end
  put(T, x, y, h)
  if T.gc > 0 then
    T.gc = T.gc - 1
    if T.gc == 2 then
      T.gates[#T.gates + 1] = T.head
      T.newGate = T.head
    end
  end
  -- forget chokes that left the faded tail
  while C[1] and C[1] < T.tail - M.FADE - 2 do
    for k2 = 1, #C do C[k2] = C[k2 + 1] end
  end
end

-- coupled hands: D follows S; mode 2 mirror, 3 copy, 4 invert (mirror + upside down); mid2 = lo + hi
function M.copy(D, S, mode, mid2)
  D.head, D.tail, D.len, D.cam, D.hover, D.newGate = S.head, S.tail, S.len, S.cam, S.hover, S.newGate
  D.rt = S.rt
  local i = idx(S.head)
  local x, y, h = S.x[i], S.y[i], S.h
  if mode ~= 3 then x, h = mid2 - x, pi - h end
  if mode == 4 then y, h = mid2 - y, -h end
  D.x[i], D.y[i], D.hx, D.hy, D.h = x, y, x, y, h
  local SC, DC = S.chokes, D.chokes
  for k = 1, #SC do DC[k] = SC[k] end
  for k = #DC, #SC + 1, -1 do DC[k] = nil end
  if S.newGate then D.gates[#D.gates + 1] = S.newGate end
end

-- age of point n: 0 solid, 1..3 fading
local function age(n, tail)
  if n >= tail then return 0 end
  return 1 + floor((tail - 1 - n) / 3)
end

-- rounded end at point n facing (c, s)
local function cap(T, n, xo, c, s, pat)
  local i = idx(n)
  local x, y, rt = T.x[i] + xo, T.y[i] - T.cam, rad(T, n)
  local px, py
  for a = 0, 8 do
    local nx = floor(x + rt * (c * CA[a] - s * SA[a]) + 0.5)
    local ny = floor(y + rt * (s * CA[a] + c * SA[a]) + 0.5)
    if px then draw.line(px, py, nx, ny, pat) end
    px, py = nx, ny
  end
end

-- outline: two offset polylines + rounded ends, fading behind the tail, gate posts
function M.draw(T, xo, v)
  local tail, head, yo = T.tail, T.head, T.cam
  local first = tail - M.FADE
  if first < 1 then first = 1 end
  -- ~4 px between vertices, but never more than MAXV vertices (draw-call budget at high speed)
  local stride = floor(M.STEP_PX / v + 0.5)
  local need = math.ceil((head - first + 1) / M.MAXV)
  if stride < need then stride = need end
  if stride < 1 then stride = 1 end
  local X, Y = T.x, T.y
  local lx, ly, rx, ry, pa, pr
  for n = first, head do
    local r = rad(T, n)
    if n == first or n == head or n % stride == 0 or r ~= pr then
      local i = idx(n)
      local c, s = dir(T, n, first, head)
      local x, y, ox, oy = X[i] + xo, Y[i] - yo, -s * r, c * r
      local nlx, nly = floor(x + ox + 0.5), floor(y + oy + 0.5)
      local nrx, nry = floor(x - ox + 0.5), floor(y - oy + 0.5)
      if lx then
        local pat = draw.PAT[pa]
        draw.line(lx, ly, nlx, nly, pat)
        draw.line(rx, ry, nrx, nry, pat)
      end
      lx, ly, rx, ry, pa = nlx, nly, nrx, nry, age(n, tail)
    end
    pr = r
  end
  local c, s = dir(T, head, first, head)
  cap(T, head, xo, c, s, SOLID)
  c, s = dir(T, first, first, head)
  cap(T, first, xo, -c, -s, draw.PAT[age(first, tail)])
  -- gate posts: short ticks just outside both walls
  for k = 1, #T.gates do
    local n = T.gates[k]
    if n >= tail and n <= head then
      local i = idx(n)
      local x, y, r = X[i] + xo, Y[i] - yo, rad(T, n)
      local gc, gs = dir(T, n, first, head)
      local nx, ny = -gs, gc
      draw.line(floor(x + nx * (r + 1) + 0.5), floor(y + ny * (r + 1) + 0.5),
        floor(x + nx * (r + 3) + 0.5), floor(y + ny * (r + 3) + 0.5), SOLID)
      draw.line(floor(x - nx * (r + 1) + 0.5), floor(y - ny * (r + 1) + 0.5),
        floor(x - nx * (r + 3) + 0.5), floor(y - ny * (r + 3) + 0.5), SOLID)
    end
  end
end

-- squared distance from (qx, qy) to segment n -> n+1; returns d2, unclamped projection t and the
-- tunnel radius at the projected point (chokes narrow smoothly between points)
local function seg(T, n, qx, qy)
  local i, j = idx(n), idx(n + 1)
  local ax, ay = T.x[i], T.y[i]
  local dx, dy = T.x[j] - ax, T.y[j] - ay
  local l2 = dx * dx + dy * dy
  local t = 0
  if l2 > 0 then t = ((qx - ax) * dx + (qy - ay) * dy) / l2 end
  local tc = t < 0 and 0 or (t > 1 and 1 or t)
  local ex, ey = ax + dx * tc - qx, ay + dy * tc - qy
  local ra = rad(T, n)
  return ex * ex + ey * ey, t, ra + (rad(T, n + 1) - ra) * tc
end

local function scan(T, a, b, qx, qy)
  local best, bn, bt, br = 1e9, a, 0, 0
  for n = a, b do
    local d2, t, r = seg(T, n, qx, qy)
    if d2 < best then best, bn, bt, br = d2, n, t, r end
  end
  return best, bn, bt, br
end

-- distance check against the solid part (tail..head); qy is world y in scroll mode
-- returns d2, true when the tail has just passed the quad (behind the tail point, near it), and the radius
function M.near(T, qx, qy)
  local tail, head = T.tail, T.head
  if head == tail then
    local i = idx(head)
    local ex, ey = T.x[i] - qx, T.y[i] - qy
    return ex * ex + ey * ey, false, rad(T, head)
  end
  local a, b = T.near - 12, T.near + 12
  if a < tail then a = tail end
  if b > head - 1 then b = head - 1 end
  local d2, n, t, r
  if a <= b then d2, n, t, r = scan(T, a, b, qx, qy) end
  -- full scan when the window says "out" or its best is on a window edge (the quad may be past it)
  if not d2 or d2 > r * r or (n == a and a > tail) or (n == b and b < head - 1) then
    d2, n, t, r = scan(T, tail, head - 1, qx, qy)
  end
  T.near = n
  -- "tail" only while the quad is still within the rounded end it just slipped off
  return d2, n == tail and t < 0 and d2 <= r * r, r
end

return M
