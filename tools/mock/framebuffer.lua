-- 128x64 1-bit framebuffer with EdgeTX stdlcd pixel semantics and PBM/ASCII/emoji export.
-- 1 = pixel on = dark on the radio.
local W, H = 128, 64
local FORCE, ERASE = 0x02, 0x04

local FB = {}
FB.__index = FB

function FB.new()
  local fb = setmetatable({ W = W, H = H, p = {} }, FB)
  fb:clear()
  return fb
end

function FB:clear()
  local p = self.p
  for i = 1, W * H do p[i] = 0 end
end

function FB:get(x, y)
  if x < 0 or y < 0 or x >= W or y >= H then return 0 end
  return self.p[y * W + x + 1]
end

-- lcdMaskPoint: FORCE sets, ERASE clears, default XOR
function FB:mask(x, y, att)
  local i = y * W + x + 1
  if att % 4 >= 2 then self.p[i] = 1
  elseif att % 8 >= 4 then self.p[i] = 0
  else self.p[i] = 1 - self.p[i] end
end

function FB:copy()
  local c = FB.new()
  for i = 1, W * H do c.p[i] = self.p[i] end
  return c
end

function FB:equals(o)
  for i = 1, W * H do if self.p[i] ~= o.p[i] then return false end end
  return true
end

function FB:diffCount(o)
  local n = 0
  for i = 1, W * H do if self.p[i] ~= o.p[i] then n = n + 1 end end
  return n
end

function FB:pbm()
  local rows = { "P1", W .. " " .. H }
  for y = 0, H - 1 do
    rows[#rows + 1] = table.concat(self.p, "", y * W + 1, y * W + W)
  end
  return table.concat(rows, "\n") .. "\n"
end

-- parse a P1 PBM (whitespace tolerant)
function FB.fromPbm(text)
  local fb = FB.new()
  local body = text:gsub("#[^\n]*", "")
  local w, h, rest = body:match("^%s*P1%s+(%d+)%s+(%d+)(.*)$")
  assert(tonumber(w) == W and tonumber(h) == H, "PBM must be P1 128x64")
  local i = 0
  for d in rest:gmatch("[01]") do
    i = i + 1
    fb.p[i] = tonumber(d)
  end
  assert(i == W * H, "PBM truncated")
  return fb
end

function FB:ascii(on, off)
  on, off = on or "#", off or "."
  local out = {}
  for y = 0, H - 1 do
    local r = {}
    for x = 0, W - 1 do r[#r + 1] = self.p[y * W + x + 1] == 1 and on or off end
    out[#out + 1] = table.concat(r)
  end
  return table.concat(out, "\n") .. "\n"
end

-- same map format as the mockups: ⬜️ = lit pixel
function FB:emoji() return self:ascii("\226\172\156\239\184\143", "\226\172\155\239\184\143") end

FB.FORCE, FB.ERASE = FORCE, ERASE
return FB
