-- Static screens: WARN, TITLE, SETTINGS, CENTER, countdown box, PAUSE, CRASHED.
local config = require("config")
local input = require("input")
local draw = require("draw")

local M = {}

function M.center(y, s, flags)
  lcd.drawText(64, y, s, (flags or 0) + CENTER)
end

-- text in reverse video: draw it centered, then XOR a box around it
local function boxed(y, s)
  M.center(y + 2, s)
  local right = lcd.getLastRightPos()
  local w = 2 * (right - 64) - 1 -- text width (CENTER puts ceil(w/2) right of x=64)
  lcd.drawFilledRectangle(right - w - 2, y, w + 3, 11)
end

local function rule() lcd.drawLine(8, 18, 119, 18, DOTTED, FORCE) end

function M.warn(modelName)
  M.center(2, "RF WARNING", DBLSIZE)
  rule()
  M.center(22, "RADIO KEEPS SENDING")
  M.center(31, "STICKS TO " .. (modelName or "YOUR MODEL"))
  M.center(40, "DISARM / POWER OFF")
  boxed(51, "[ENT] I KNOW")
end

-- sub: mode and preset (or NO SAVE)
function M.title(best, sub)
  M.center(3, "GATERUSH", DBLSIZE)
  M.center(21, sub)
  draw.quadIcon(27, 37)
  draw.quadIcon(100, 37)
  M.center(34, best)
  M.center(46, "ENT:ARM  RTN:EXIT")
  M.center(56, "HOLD ENT: SETTINGS")
end

M.MENU = {} -- config items + RESET BEST + EXIT
for i = 1, #config.ITEMS do M.MENU[i] = config.ITEMS[i] end
M.MENU[#M.MENU + 1] = { name = "RESET BEST", action = "reset" }
M.MENU[#M.MENU + 1] = { name = "EXIT", action = "exit" }

local PAGES = math.ceil(#M.MENU / 5)

function M.settings(sel, editing, confirm)
  local page = math.ceil(sel / 5)
  lcd.drawText(2, 1, "SETTINGS", 0)
  lcd.drawText(90, 1, page .. "/" .. PAGES, 0)
  lcd.drawLine(0, 9, 127, 9, SOLID, FORCE)
  for row = 1, 5 do
    local i = (page - 1) * 5 + row
    local it, y = M.MENU[i], 2 + row * 10
    if not it then break end
    local val = ""
    if it.key then val = config.label(it)
    elseif it.action == "reset" then val = confirm and "ENT?" or "..." end
    if i == sel and editing then val = "<" .. val .. ">" end
    lcd.drawText(4, y, it.name, 0)
    lcd.drawText(78, y, val, 0)
    if i == sel then lcd.drawFilledRectangle(0, y - 1, 124, 9) end
  end
  lcd.drawLine(126, 11, 126, 62, SOLID, FORCE)
  local h = math.floor(52 / PAGES)
  lcd.drawFilledRectangle(125, 11 + (page - 1) * h, 3, h, FORCE)
end

-- 21x21 box with crosshair and the stick dot, hold bar below
local function stickbox(cx, cy, sx, sy, hold)
  lcd.drawRectangle(cx - 10, cy - 10, 21, 21, FORCE)
  lcd.drawLine(cx - 8, cy, cx + 8, cy, DOTTED, FORCE)
  lcd.drawLine(cx, cy - 8, cx, cy + 8, DOTTED, FORCE)
  local dx, dy = math.floor(sx * 8 / 1024 + 0.5), math.floor(-sy * 8 / 1024 + 0.5)
  lcd.drawFilledRectangle(cx + dx - 1, cy + dy - 1, 3, 3, FORCE)
  lcd.drawRectangle(cx - 11, 52, 22, 3, FORCE)
  local w = math.floor(22 * hold + 0.5)
  if w > 0 then lcd.drawFilledRectangle(cx - 11, 52, w, 3, FORCE) end
end

function M.centerSticks(holdL, holdR)
  lcd.drawLine(64, 0, 64, 63, SOLID, FORCE)
  lcd.drawText(10, 4, "CENTER", 0)
  lcd.drawText(75, 4, "CENTER", 0)
  lcd.drawText(10, 12, "STICKS", 0)
  lcd.drawText(75, 12, "STICKS", 0)
  local r = input.raw
  stickbox(32, 38, r[1], r[2], holdL)
  stickbox(97, 38, r[3], r[4], holdR)
end

-- "3" "2" "1" in an 18x24 box per half, above or below the quad so it never hides it
function M.count(n, qy, on)
  for side = 1, 2 do
    if on[side] then
      local x = side == 1 and 23 or 88
      local y = qy[side] > 32 and 3 or 38
      lcd.drawFilledRectangle(x, y, 18, 24, ERASE)
      lcd.drawRectangle(x, y, 18, 24, FORCE)
      draw.glyph(draw.big[n], x + 3, y + 2)
    end
  end
end

function M.pause()
  lcd.drawFilledRectangle(14, 20, 100, 24, ERASE)
  lcd.drawRectangle(14, 20, 100, 24, FORCE)
  lcd.drawRectangle(16, 22, 96, 20, FORCE)
  M.center(24, "PAUSED")
  M.center(34, "ENT:GO RTN:QUIT")
end

-- result screen; c = { title, lines = { up to 3 }, rec, newBest }; a new best is shown in reverse video
function M.crashed(c)
  M.center(2, c.title, DBLSIZE)
  rule()
  for i = 1, #c.lines do M.center(11 + i * 9, c.lines[i]) end
  if c.rec then
    M.center(47, c.rec)
    if c.newBest then lcd.drawFilledRectangle(0, 46, 128, 9) end
  end
  M.center(56, "[ENT] RE-ARM")
end

return M
