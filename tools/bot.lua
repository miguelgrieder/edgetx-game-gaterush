-- Artificial player: drives both sticks toward the centerline point near the tunnel head.
-- bot.new{delay = frames, noise = px, lead = points, seed = n, rearm = bool} -> input function for the harness
local B = {}

function B.new(o)
  o = o or {}
  local delay, noise, lead = o.delay or 0, o.noise or 0, o.lead or 4
  local seed = o.seed or 1
  local hist = {} -- delayed stick commands, ring of delay+1 entries
  local phaseT = 0

  local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647 * 2 - 1
  end

  -- half-local px -> stick value (inverse of input.pos)
  local function stick(input, p, invert)
    local v = (p - input.lo) / (input.hi - input.lo) * 2048 - 1024
    if v > 1024 then v = 1024 elseif v < -1024 then v = -1024 end
    v = math.floor(v + 0.5)
    return invert and -v or v
  end

  -- target: the centerline point `lead` points behind the head. The hand follows it with an
  -- exponential lag (gain per frame) so it cuts corners like a human, plus a wandering error of ~noise px.
  local gain = o.gain or 1 / (1 + delay)
  local pos = { { 32, 32 }, { 32, 32 } }
  local err = { 0, 0, 0, 0 }
  local function aim(ctx, side)
    local T, track, input = ctx.game.tracks[side], ctx.track, ctx.input
    local n = T.head - lead
    local tail = track.tail(T)
    if n < tail then n = tail end
    local i = (n - 1) % track.CAP + 1
    return T.x[i], T.y[i] - (T.cam or 0) -- screen y in scroll mode
  end
  local function hand(side, tx, ty, input)
    local p = pos[side]
    p[1] = p[1] + (tx - p[1]) * gain
    p[2] = p[2] + (ty - p[2]) * gain
    local e1, e2 = side * 2 - 1, side * 2
    err[e1] = err[e1] * 0.8 + rnd() * noise * 0.6
    err[e2] = err[e2] * 0.8 + rnd() * noise * 0.6
    return stick(input, p[1] + err[e1], false), stick(input, p[2] + err[e2], true)
  end

  return function(frame, _, ctx)
    -- menus (warning 1, title 2, center sticks 4, result 9): ENTER through, sticks centered
    local st = ctx.h.app.state()
    if st <= 4 or st == 9 then
      if st <= 2 and (frame == 10 or frame == 20) then return 0, 0, 0, 0, "enter" end
      if st == 9 and o.rearm then
        phaseT = phaseT + 1
        if phaseT == 15 then phaseT = 0; return 0, 0, 0, 0, "enter" end
      end
      return 0, 0, 0, 0
    end
    local ax, ay = aim(ctx, 1)
    local bx, by = aim(ctx, 2)
    hist[frame % (delay + 1)] = { ax, ay, bx, by }
    local d = hist[(frame - delay) % (delay + 1)] or { ax, ay, bx, by }
    local lx, ly = hand(1, d[1], d[2], ctx.input)
    local rx, ry = hand(2, d[3], d[4], ctx.input)
    -- stick mode 2: left = rud (X) + thr (Y), right = ail (X) + ele (Y)
    return rx, ry, ly, lx
  end
end

return B
