-- GateRush entry: state machine, fixed 50 ms timestep, events, backlight.
local config = require("config")
local stats = require("stats")
local input = require("input")
local game = require("game")
local screens = require("screens")
local fx = require("fx")

local WARN, TITLE, SETTINGS, CENTER, COUNTDOWN, PLAY, PAUSE, RESUME, CRASHED, WRECK = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

local state, last, acc, frame = WARN, 0, 0, 0
local ignoreUntil = 0
local eatEnter = false -- the ENTER release that follows a long press
local saveOk, modelName, best, sub = true, nil, "", ""
local sel, editing, confirm = 1, false, false
local hold = { 0, 0 }
local count = 0 -- countdown / crash animation ticks
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

-- score as shown: m:ss, or % in sprint
local function fmt(v)
  if config.v.MODE == 2 then return v and v .. "%" or "--%" end
  return stats.fmt(v)
end

local function refreshBest()
  local v = config.v
  best = v.MODE == 3 and "FREE FLIGHT" or "BEST " .. fmt(stats.best(config.hash()))
  sub = saveOk and config.MODES[v.MODE] .. "  " .. config.PRESETS[v.PRESET] or "NO SAVE"
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

-- result screen; quit = RTN from pause (never recorded); zen runs are never recorded
local function finish(quit)
  local mode, key = config.v.MODE, config.hash()
  local time, acc, seed = stats.fmt(game.ms()), "ACC " .. game.acc() .. "%", "SEED " .. game.seed
  local gates = "GATES " .. game.gates
  local record = not quit and mode ~= 3
  crash.newBest = record and stats.add(key, game.score())
  if record then stats.save() end
  if mode == 2 then
    crash.title = quit and "QUIT" or "FINISH"
    crash.lines = { acc .. "  " .. gates, seed }
  elseif mode == 3 then
    crash.title = "ZEN"
    crash.lines = { "TIME " .. time .. "  " .. acc, gates .. "  " .. seed }
  else
    local line1 = "TIME " .. time .. "  " .. (quit and "QUIT" or game.CAUSE[game.crashed])
    if #line1 > 21 then line1 = "TIME " .. time .. " " .. (quit and "QUIT" or game.CAUSE[game.crashed]) end
    crash.title = quit and "QUIT" or "CRASHED"
    crash.lines = { line1, gates .. "  " .. acc, "SCORE " .. fmt(game.score()) .. "  " .. seed }
  end
  crash.rec = nil
  if mode ~= 3 then
    crash.rec = (crash.newBest and "NEW BEST!" or "BEST " .. fmt(stats.best(key))) .. "  AVG " .. fmt(stats.avg(key))
  end
  flash = quit and 0 or 2
  go(CRASHED)
end

local function leaveSettings()
  saveOk = config.save()
  input.setRange(config.radius())
  editing, confirm = false, false
  refreshBest()
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
    -- practice modes only need the stick of the hand in play
    local mode = config.v.MODE
    for side = 1, 2 do
      local used = (side == 1 and mode ~= 5) or (side == 2 and mode ~= 4)
      hold[side] = (input.centered(side) or not used) and hold[side] + steps or 0
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
      if game.crashed then
        state, count = WRECK, 0
        break
      end
      if game.finished then finish(false) break end
    end
  elseif state == WRECK then
    count = count + steps -- props fly off for 0.6 s, then the result
    if count >= 12 then finish(false) end
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
  elseif state == TITLE then screens.title(best, sub)
  elseif state == SETTINGS then screens.settings(sel, editing, confirm)
  elseif state == CENTER then screens.centerSticks(hold[1] / 10, hold[2] / 10)
  elseif state == CRASHED and flash == 0 then screens.crashed(crash)
  else
    game.drawWorld()
    if state == COUNTDOWN or state == RESUME then
      local n = 3 - math.floor(count / 20)
      screens.count(n < 1 and 1 or n, game.qy, game.on)
    end
    if state == WRECK then game.drawDebris(count) else game.drawQuads(frame) end
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
  if state >= CENTER and state ~= PAUSE and state ~= CRASHED then lcd.resetBacklightTimeout() end -- WRECK too
  render()
  return r
end

return { init = init, run = run }
