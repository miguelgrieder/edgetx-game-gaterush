-- Menu group (loaded only outside a run): RF warning, title, settings, center sticks, result screen.
local use = ...
local config = use("config")
local input = use("input")
local stats = use("stats")

local M = {}

-- MARGIN, CRASH_DELAY, SPEED, SPEED_ACCEL, CURVE_ACCEL, TRACK_LEN of each preset
local PRESET_V = { { 3, 10, 3, 1, 2, 35 }, { 2, 5, 4, 2, 5, 25 }, { 1, 3, 5, 3, 6, 25 }, { 0, 2, 6, 4, 8, 20 } }
local DIFF = { "MARGIN", "CRASH_DELAY", "SPEED", "SPEED_ACCEL", "CURVE_ACCEL", "TRACK_LEN" }

-- PRESET follows the six difficulty values: the matching preset, else CUSTOM
function M.sync()
  config.v.PRESET = 5
  for p = 1, 4 do
    local same = true
    for i = 1, 6 do if config.v[DIFF[i]] ~= PRESET_V[p][i] then same = false end end
    if same then config.v.PRESET = p end
  end
end

-- step the value of item it by dir (+1/-1), clamped; choosing a preset loads its values
function M.change(it, dir)
  local nv = config.v[it.key] + dir * (it.step or 1)
  if nv < it.lo then nv = it.lo elseif nv > it.hi then nv = it.hi end
  config.v[it.key] = nv
  if it.key == "PRESET" then
    if nv < 5 then
      for i = 1, 6 do config.v[DIFF[i]] = PRESET_V[nv][i] end
    end
  else
    M.sync()
  end
end

-- text shown in the settings list
function M.label(it)
  local v = config.v[it.key]
  if it.key == "MARGIN" then return v .. " PX" end
  if it.key == "CRASH_DELAY" then return math.floor(v / 10) .. "." .. (v % 10) .. " S" end
  if it.names then return it.names[v - it.lo + 1] end
  if it.key == "SEED" and v == 0 then return "RANDOM" end
  return tostring(v)
end


M.saveOk = true
M.sel, M.editing, M.confirm = 1, false, false
local best, sub = "", ""
local res = {} -- result screen: title, lines, rec, newBest

local function center(y, s, flags)
  lcd.drawText(64, y, s, (flags or 0) + CENTER)
end

-- text in reverse video: draw it centered, then XOR a box around it
local function boxed(y, s)
  center(y + 2, s)
  local right = lcd.getLastRightPos()
  local w = 2 * (right - 64) - 1 -- text width (CENTER puts ceil(w/2) right of x=64)
  lcd.drawFilledRectangle(right - w - 2, y, w + 3, 11)
end

local function rule() lcd.drawLine(8, 18, 119, 18, DOTTED, FORCE) end

-- score as shown: m:ss, or % in sprint
local function fmt(v)
  if config.v.MODE == 2 then return v and v .. "%" or "--%" end
  return stats.fmt(v)
end

-- title texts for the current settings
function M.refresh()
  local v = config.v
  best = v.MODE == 3 and "FREE FLIGHT" or "BEST " .. fmt(stats.best(config.hash()))
  sub = M.saveOk and config.MODES[v.MODE] .. "  " .. config.PRESETS[v.PRESET] or "NO SAVE"
end

function M.warn(modelName)
  center(2, "RF WARNING", DBLSIZE)
  rule()
  center(22, "RADIO KEEPS SENDING")
  center(31, "STICKS TO " .. (modelName or "YOUR MODEL"))
  center(40, "DISARM / POWER OFF")
  boxed(51, "[ENT] I KNOW")
end

-- 11x11 quad silhouette for the title
local function icon(x, y)
  lcd.drawFilledRectangle(x - 1, y - 1, 3, 3, FORCE)
  for sx = -1, 1, 2 do
    for sy = -1, 1, 2 do
      lcd.drawLine(x + 2 * sx, y + 2 * sy, x + 4 * sx, y + 4 * sy, SOLID, FORCE)
      local cx, cy = x + 5 * sx, y + 5 * sy
      lcd.drawPoint(cx - 1, cy, FORCE)
      lcd.drawPoint(cx + 1, cy, FORCE)
      lcd.drawPoint(cx, cy - 1, FORCE)
      lcd.drawPoint(cx, cy + 1, FORCE)
    end
  end
end
M.icon = icon

function M.title()
  center(3, "GATERUSH", DBLSIZE)
  center(21, sub)
  icon(27, 37)
  icon(100, 37)
  center(34, best)
  center(46, "ENT:ARM  RTN:EXIT")
  center(56, "HOLD ENT: SETTINGS")
end

M.MENU = {} -- config items + RESET BEST + EXIT
for i = 1, #config.ITEMS do M.MENU[i] = config.ITEMS[i] end
M.MENU[#M.MENU + 1] = { name = "RESET BEST", action = "reset" }
M.MENU[#M.MENU + 1] = { name = "EXIT", action = "exit" }
local PAGES = math.ceil(#M.MENU / 5)

function M.settings()
  local sel = M.sel
  local page = math.ceil(sel / 5)
  lcd.drawText(2, 1, "SETTINGS", 0)
  lcd.drawText(90, 1, page .. "/" .. PAGES, 0)
  lcd.drawLine(0, 9, 127, 9, SOLID, FORCE)
  for row = 1, 5 do
    local i = (page - 1) * 5 + row
    local it, y = M.MENU[i], 2 + row * 10
    if not it then break end
    local val = ""
    if it.key then val = M.label(it)
    elseif it.action == "reset" then val = M.confirm and "ENT?" or "..." end
    if i == sel and M.editing then val = "<" .. val .. ">" end
    lcd.drawText(4, y, it.name, 0)
    lcd.drawText(78, y, val, 0)
    if i == sel then lcd.drawFilledRectangle(0, y - 1, 124, 9) end
  end
  lcd.drawLine(126, 11, 126, 62, SOLID, FORCE)
  local h = math.floor(52 / PAGES)
  lcd.drawFilledRectangle(125, 11 + (page - 1) * h, 3, h, FORCE)
end

-- one settings event: "next" / "prev" / "enter" / "exit"; returns true when leaving the menu
function M.settingsEvent(e)
  local it = M.MENU[M.sel]
  if M.editing then
    if e == "next" then M.change(it, 1)
    elseif e == "prev" then M.change(it, -1)
    elseif e == "enter" or e == "exit" then M.editing = false end
    M.refresh()
    return false
  end
  if e == "next" then M.sel, M.confirm = M.sel % #M.MENU + 1, false
  elseif e == "prev" then M.sel, M.confirm = (M.sel - 2) % #M.MENU + 1, false
  elseif e == "exit" then return true
  elseif e == "enter" then
    if it.key then M.editing = true
    elseif it.action == "exit" then return true
    elseif M.confirm then
      stats.reset(config.hash())
      stats.save()
      M.confirm = false
      M.refresh()
    else M.confirm = true end
  end
  return false
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

-- record a finished run and build the result screen.
-- r = { quit, ms, gates, acc, seed, score, cause } from the play group (already unloaded)
function M.finish(r)
  local mode, key = config.v.MODE, config.hash()
  local time, acc, seed = stats.fmt(r.ms), "ACC " .. r.acc .. "%", "SEED " .. r.seed
  local gates = "GATES " .. r.gates
  local record = not r.quit and mode ~= 3
  res.newBest = record and stats.add(key, r.score)
  if record then stats.save() end
  if mode == 2 then
    res.title = r.quit and "QUIT" or "FINISH"
    res.lines = { acc .. "  " .. gates, seed }
  elseif mode == 3 then
    res.title = "ZEN"
    res.lines = { "TIME " .. time .. "  " .. acc, gates .. "  " .. seed }
  else
    local cause = r.quit and "QUIT" or r.cause
    local line1 = "TIME " .. time .. "  " .. cause
    if #line1 > 21 then line1 = "TIME " .. time .. " " .. cause end
    res.title = r.quit and "QUIT" or "CRASHED"
    res.lines = { line1, gates .. "  " .. acc, "SCORE " .. fmt(r.score) .. "  " .. seed }
  end
  res.rec = nil
  if mode ~= 3 then
    res.rec = (res.newBest and "NEW BEST!" or "BEST " .. fmt(stats.best(key))) .. "  AVG " .. fmt(stats.avg(key))
  end
  M.res = res
end

-- result screen; a new best is shown in reverse video
function M.result()
  center(2, res.title, DBLSIZE)
  rule()
  for i = 1, #res.lines do center(11 + i * 9, res.lines[i]) end
  if res.rec then
    center(47, res.rec)
    if res.newBest then lcd.drawFilledRectangle(0, 46, 128, 9) end
  end
  center(56, "[ENT] RE-ARM")
end

stats.load()
M.sync()
M.refresh()
return M
