-- Colour screens only (loaded by main when LCD_W > 212): the game draws for a 128x64 black & white screen,
-- so this swaps the global lcd for one that scales everything S times, centred, in black on white.
-- FORCE/ERASE only exist on B&W radios: they are defined here (their B&W values) and drawn as black and
-- white, and a fill without flags (B&W: XOR, used under highlighted text) becomes invertRect.
-- getLastRightPos only exists on B&W: it is worked out from sizeText. Fonts go up a size (std -> XL,
-- small -> L, double -> XXL) to match the scale.
local L = lcd
local S = math.floor(math.min(LCD_W / 128, LCD_H / 64))
local X0, Y0 = math.floor((LCD_W - 128 * S) / 2), math.floor((LCD_H - 64 * S) / 2)
local BLACK, WHITE = L.RGB(0, 0, 0), L.RGB(255, 255, 255)
local XS, XL = math.floor(SMLSIZE / 256) % 16, math.floor(DBLSIZE / 256) % 16 -- font indexes (flags 0x0F00)
local right = 0 -- getLastRightPos, in game pixels

-- B&W flags -> colour flags; text gets the next font size up
local function colour(f)
  if f == 2 then return BLACK elseif f == 4 then return WHITE end -- FORCE, ERASE
  return f or BLACK
end
local function font(f)
  f = f or 0
  local i = math.floor(f / 256) % 16
  return f - i * 256 + (i == XL and XXLSIZE or i == XS and MIDSIZE or DBLSIZE) + BLACK
end
local function text(draw, x, y, s, f)
  local g = font(f)
  local sx = X0 + x * S
  draw(sx, Y0 + y * S, s, g)
  local w = L.sizeText(tostring(s), g)
  local r = f and f % 16 >= 8 and sx or (f and f % 8 >= 4 and sx + w / 2 or sx + w) -- RIGHT 0x08, CENTER 0x04
  right = (r - X0) / S
end

local C = setmetatable({}, { __index = L }) -- anything not wrapped below (resetBacklightTimeout) as it is
function C.clear() L.clear(WHITE) end
function C.drawPoint(x, y, f) L.drawFilledRectangle(X0 + x * S, Y0 + y * S, S, S, colour(f)) end
function C.drawLine(x1, y1, x2, y2, pat, f)
  local h = math.floor(S / 2) -- through the middle of the big pixels
  L.drawLine(X0 + x1 * S + h, Y0 + y1 * S + h, X0 + x2 * S + h, Y0 + y2 * S + h, pat, colour(f))
end
function C.drawFilledRectangle(x, y, w, h, f)
  if not f or f == 0 then L.invertRect(X0 + x * S, Y0 + y * S, w * S, h * S) -- the B&W XOR fill
  else L.drawFilledRectangle(X0 + x * S, Y0 + y * S, w * S, h * S, colour(f)) end
end
function C.drawRectangle(x, y, w, h, f) L.drawRectangle(X0 + x * S, Y0 + y * S, w * S, h * S, colour(f), S) end
function C.drawText(x, y, s, f) text(L.drawText, x, y, s, f) end
function C.drawNumber(x, y, n, f) text(L.drawNumber, x, y, n, f) end
function C.getLastRightPos() return right end

lcd, LCD_W, LCD_H, FORCE, ERASE = C, 128, 64, 2, 4
