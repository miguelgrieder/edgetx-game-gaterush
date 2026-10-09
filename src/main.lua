-- GateRush entry: state machine, fixed 50 ms timestep, events, backlight.
local config = require("config")
local stats = require("stats")
local input = require("input")
local game = require("game")
local screens = require("screens")
local fx = require("fx")

local WARN, TITLE, SETTINGS, CENTER, COUNTDOWN, PLAY, PAUSE, RESUME, CRASHED = 1, 2, 3, 4, 5, 6, 7, 8, 9

local state, last, acc, frame = WARN, 0, 0, 0
local ignoreUntil = 0
local eatEnter = false -- the ENTER release that follows a long press
local saveOk, modelName, best = true, nil, "--:--"
local sel, editing, confirm = 1, false, false
local hold = { 0, 0 }
local count = 0 -- countdown ticks
local flash = 0
local crash = {}

-- events (virtual + legacy; some constants are nil on some radios)
local function is(e, a, b, c, d)
  return e ~= 0 and (e == a or e == b or e == c or e == d)
end
local function isEnter(e) return is(e, EVT_VIRTUAL_ENTER, EVT_ENTER_BREAK, EVT_ROT_BREAK) end
local function isLong(e) return is(e, EVT_VIRTUAL_ENTER_LONG, EVT_ENTER_LONG, EVT_ROT_LONG) end
local function isExit(e) return is(e, EVT_VIRTUAL_EXIT, EVT_EXIT_BREAK) end
-- encoder, +/- keys or PAGE keys
local function isNext(e)
  return is(e, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_INC_REPT, EVT_VIRTUAL_NEXT_PAGE, EVT_PLUS_BREAK)
end
local function isPrev(e)
  return is(e, EVT_VIRTUAL_PREV, EVT_VIRTUAL_DEC_REPT, EVT_VIRTUAL_PREV_PAGE, EVT_MINUS_BREAK)
end

local function refreshBest()
  best = stats.fmt(stats.best(config.hash()))
end

local function go(s)
  state = s
  ignoreUntil = getTime() + 30
  if s == TITLE then refreshBest() end
  if s == CENTER then hold[1], hold[2] = 0, 0 end
  if s == COUNTDOWN then
    game.spawn(getTime())
    count = 0
  end
  if s == RESUME then count = 0 end
end

local function finish(quit)
  local key = config.hash()
  local ms = game.ms()
  local newBest = false
  if not quit then
    newBest = stats.add(key, ms)
    stats.save()
  end
  local cause = quit and "QUIT" or game.CAUSE[game.crashed]
  local line1 = "TIME " .. stats.fmt(ms) .. "  " .. cause
  if #line1 > 21 then line1 = "TIME " .. stats.fmt(ms) .. " " .. cause end
  crash.line1 = line1
  crash.line2 = "BEST " .. stats.fmt(stats.best(key)) .. "  AVG " .. stats.fmt(stats.avg(key))
  crash.newBest = newBest
  flash = quit and 0 or 2
  go(CRASHED)
end

local function leaveSettings()
  saveOk = config.save()
  input.setRange(config.radius())
  editing, confirm = false, false
  go(TITLE)
end

local function settingsEvent(e)
  local it = screens.MENU[sel]
  if editing then
    if isNext(e) then config.change(it, 1)
    elseif isPrev(e) then config.change(it, -1)
    elseif isEnter(e) or isExit(e) then editing = false end
    return
  end
  if isNext(e) then sel = sel % #screens.MENU + 1; confirm = false
  elseif isPrev(e) then sel = (sel - 2) % #screens.MENU + 1; confirm = false
  elseif isExit(e) then leaveSettings()
  elseif isEnter(e) then
    if it.key then editing = true
    elseif it.action == "exit" then leaveSettings()
    elseif confirm then
      stats.reset(config.hash())
      stats.save()
      confirm = false
    else confirm = true end
  end
end

-- countdown of 60 ticks with a beep per second; returns true when done
local function countdown(steps)
  for _ = 1, steps do
    if count % 20 == 0 then fx.beep(count < 60 and 600 or 1200, count < 60 and 80 or 250) end
    count = count + 1
    if count > 60 then return true end
  end
  return false
end

local function update(e, steps)
  if state == WARN then
    if isEnter(e) then go(TITLE) elseif isExit(e) then return 1 end
  elseif state == TITLE then
    if isLong(e) then
      killEvents(e)
      eatEnter = true
      sel, editing, confirm = 1, false, false
      go(SETTINGS)
    elseif isEnter(e) then go(CENTER)
    elseif isExit(e) then return 1 end
  elseif state == SETTINGS then
    settingsEvent(e)
    refreshBest()
  elseif state == CENTER then
    if isExit(e) then go(TITLE) return 0 end
    for side = 1, 2 do
      hold[side] = input.centered(side) and hold[side] + steps or 0
      if hold[side] > 10 then hold[side] = 10 end
    end
    if hold[1] >= 10 and hold[2] >= 10 then go(COUNTDOWN) end
  elseif state == COUNTDOWN or state == RESUME then
    game.moveQuads()
    if isExit(e) then
      if state == COUNTDOWN then go(TITLE) else go(PAUSE) end
    elseif countdown(steps) then
      state = PLAY
    end
  elseif state == PLAY then
    if isExit(e) then go(PAUSE) return 0 end
    game.moveQuads()
    for _ = 1, steps do
      game.tick()
      if game.crashed then finish(false) break end
    end
  elseif state == PAUSE then
    if isEnter(e) then go(RESUME) elseif isExit(e) then finish(true) end
  elseif state == CRASHED then
    if isEnter(e) then go(CENTER) elseif isExit(e) then go(TITLE) end
  end
  return 0
end

local function render()
  lcd.clear()
  if state == WARN then screens.warn(modelName)
  elseif state == TITLE then screens.title(best, saveOk)
  elseif state == SETTINGS then screens.settings(sel, editing, confirm)
  elseif state == CENTER then screens.centerSticks(hold[1] / 10, hold[2] / 10)
  elseif state == CRASHED and flash == 0 then screens.crashed(crash)
  else
    game.drawWorld()
    if state == COUNTDOWN or state == RESUME then
      local n = 3 - math.floor(count / 20)
      screens.count(n < 1 and 1 or n, game.qy)
    end
    game.drawQuads(frame)
    if state ~= COUNTDOWN then game.drawHud() end
    if state == PAUSE then screens.pause()
    elseif state == CRASHED then
      lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H) -- invert flash
      flash = flash - 1
    end
  end
end

local function init()
  config.load()
  saveOk = config.save()
  stats.load()
  input.setRange(config.radius())
  if model and model.getInfo then
    local ok, info = pcall(model.getInfo)
    if ok and info and info.name and info.name ~= "" then modelName = string.upper(string.sub(info.name, 1, 11)) end
  end
  refreshBest()
  last = getTime()
  ignoreUntil = last + 40
end

local function run(event)
  local now = getTime()
  acc = acc + now - last
  last = now
  if acc > 20 then acc = 20 end
  local steps = math.floor(acc / 5)
  acc = acc - steps * 5
  frame = frame + 1
  event = event or 0
  if eatEnter and isEnter(event) then
    eatEnter = false
    event = 0
  end
  if now < ignoreUntil then event = 0 end
  input.read(config.v.STICK_MODE)
  local r = update(event, steps)
  if state >= CENTER and state ~= PAUSE and state ~= CRASHED then lcd.resetBacklightTimeout() end
  render()
  return r
end

return { init = init, run = run }
