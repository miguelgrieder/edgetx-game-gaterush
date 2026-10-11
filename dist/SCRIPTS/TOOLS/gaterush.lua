-- TNS|GateRush|TNE
-- GateRush (generated from src/ by tools/build.lua; edit the sources)
-- GateRush entry: module loader, state machine, fixed 50 ms timestep, events, backlight.
-- The game lives in /SCRIPTS/TOOLS/GATERUSH/*.lua, loaded with loadScript (each file is compiled and
-- cached as .luac on its own: one big file ran out of memory while compiling on the radio).
-- Only one group is in memory at a time: menus (menus, stats) or play (game, track, draw, fx).
local DIR = "/SCRIPTS/TOOLS/GATERUSH/"
local loaded = {}

-- EdgeTX runs a file's .luac when it is newer than the .lua, so after an update the radio could keep
-- running the previous version. build.txt holds the build's stamp (tools/build.lua); compiled.txt that
-- stamp and the modules already recompiled for it. A module's first load under a new stamp forces the
-- recompile ("c").
local function readText(name)
  local f = io.open(DIR .. name, "r")
  if not f then return "" end
  local s = io.read(f, 400)
  io.close(f)
  return s or ""
end
local build = readText("build.txt")
local stamp = string.match(build, "%S+") -- nil: no build file (tests from src/)
local done = readText("compiled.txt")
if stamp and string.match(done, "^%S*") ~= stamp then
  done = stamp .. "\n"
  local f = io.open(DIR .. "compiled.txt", "w")
  if f then io.write(f, done) io.close(f) end
end

-- a module recompiled under this build's stamp: noted in done and in compiled.txt
local function markDone(name)
  done = done .. name .. "\n"
  local f = io.open(DIR .. "compiled.txt", "a")
  if f then io.write(f, name, "\n") io.close(f) end
end

local function use(name)
  local m = loaded[name]
  if not m then
    local fresh = not stamp or string.find(done, "\n" .. name .. "\n", 1, true)
    collectgarbage() -- compiling is the memory peak: start it with the garbage gone
    local chunk, err = loadScript(DIR .. name .. ".lua", fresh and "bt" or "btc")
    if not chunk then error(err) end
    if not fresh then markDone(name) end
    m = chunk(use)
    loaded[name] = m
  end
  return m
end

if LCD_W > 212 then use("color") end -- a colour screen: scale the 128x64 game up (before anything draws)
local config, input = use("config"), use("input")

-- The first start of a new build compiles the modules listed in build.txt, one per frame, before anything
-- else is loaded: compiling is the memory peak (a Pocket ran out of it), loading the .luac later is not
local pending, np = {}, 0
for name in string.gmatch(build, "\n(%S+)") do
  -- (color is never loaded on a B&W radio; on a colour one it was loaded, and marked done, above)
  if not string.find(done, "\n" .. name .. "\n", 1, true) and (name ~= "color" or LCD_W > 212) then
    pending[#pending + 1] = name
  end
end
local menus, game

local TITLE, SETTINGS, CENTER, COUNTDOWN, PLAY, PAUSE, RESUME, CRASHED, WRECK = 2, 3, 4, 5, 6, 7, 8, 9, 10 -- (1 was the RF warning)

local state, last, acc, frame = TITLE, 0, 0, 0
local ignoreUntil = 0
local eatEnter = false -- the ENTER release that follows a long press
local saveOk = true
local frameTicks = 5 -- smoothed time between frames (10 ms units), for the DEBUG frame rate
local hold = { 0, 0 }
local count = 0 -- countdown / crash animation ticks

-- switch the loaded group, freeing the other one first
local function menuMode()
  if game then
    loaded.game, loaded.track, loaded.draw, loaded.fx, game = nil, nil, nil, nil, nil
    collectgarbage()
  end
  if not menus then
    menus = use("menus")
    menus.saveOk = saveOk
    menus.refresh()
    collectgarbage() -- drop what loading/compiling left behind
  end
end

local function playMode()
  if menus then
    loaded.menus, loaded.stats, menus = nil, nil, nil
    collectgarbage()
  end
  if not game then
    game = use("game")
    collectgarbage()
  end
end

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

local function go(s)
  state = s
  ignoreUntil = getTime() + 30
  if s >= COUNTDOWN and s ~= CRASHED then playMode() else menuMode() end
  if s == TITLE then menus.refresh() menus.tsel = 1 end -- back on the title, ENT plays again
  if s == CENTER then hold[1], hold[2] = 0, 0 end
  if s == COUNTDOWN then game.spawn(getTime()) end
  if s == COUNTDOWN or s == RESUME then count = 0 end
end

-- result screen; quit = RTN from pause (never recorded)
local function finish(quit)
  local r = game.result(quit)
  go(CRASHED)
  menus.finish(r)
end

-- countdown of 60 ticks with a beep per second; returns true when done
local function countdown(steps)
  for _ = 1, steps do
    if count % 20 == 0 then playTone(count < 60 and 600 or 1200, count < 60 and 80 or 250, 0, PLAY_NOW) end
    count = count + 1
    if count > 60 then return true end
  end
  return false
end

local function update(e, steps)
  if state == TITLE then
    -- the menu (PLAY, SETTINGS, EXIT); holding ENT still opens the settings as a shortcut
    if isLong(e) then
      killEvents(e)
      eatEnter = true
      menus.sel, menus.editing, menus.confirm = 1, false, false
      go(SETTINGS)
    elseif isNext(e) then menus.tsel = menus.tsel % 3 + 1
    elseif isPrev(e) then menus.tsel = (menus.tsel + 1) % 3 + 1
    elseif isEnter(e) then
      if menus.tsel == 1 then go(CENTER)
      elseif menus.tsel == 2 then
        menus.sel, menus.editing, menus.confirm = 1, false, false
        go(SETTINGS)
      else return 1 end
    elseif isExit(e) then return 1 end
  elseif state == SETTINGS then
    local ev = isNext(e) and "next" or isPrev(e) and "prev" or isEnter(e) and "enter" or isExit(e) and "exit"
    if ev and menus.settingsEvent(ev) then
      saveOk = config.save()
      menus.saveOk = saveOk
      input.setRange(config.radius())
      go(TITLE)
    end
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
    count = count + steps -- props fly off for 0.6 s (the last 2 frames flash), then the result
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
  if state == TITLE then menus.title()
  elseif state == SETTINGS then menus.settings()
  elseif state == CENTER then menus.centerSticks(hold[1] / 10, hold[2] / 10)
  elseif state == CRASHED then menus.result()
  else
    game.drawWorld()
    if state == COUNTDOWN or state == RESUME then
      local n = 3 - math.floor(count / 20)
      game.count(n < 1 and 1 or n)
    end
    if state == WRECK then game.drawDebris(count) else game.drawQuads(frame) end
    if state ~= COUNTDOWN then game.drawHud() end
    if config.v.DEBUG == 1 then
      -- live frame rate and Lua memory (getUsage() on B&W radios is the slowest frame since the start)
      lcd.drawNumber(12, 57, math.floor(100 / frameTicks + 0.5), SMLSIZE)
      lcd.drawText(lcd.getLastRightPos() + 1, 57, "FPS", SMLSIZE)
      lcd.drawNumber(110, 57, math.floor(collectgarbage("count")), SMLSIZE + RIGHT)
      lcd.drawText(111, 57, "KB", SMLSIZE)
    end
    if state == PAUSE then game.pause()
    elseif state == WRECK and count >= 10 then lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H) end -- flash
  end
end

local function init()
  config.load()
  saveOk = config.save()
  input.setRange(config.radius())
  if #pending == 0 then menuMode() end -- else once the modules are compiled (run)
  last = getTime()
  ignoreUntil = last + 40
end

local function run(event)
  if np < #pending then
    np = np + 1
    local name = pending[np]
    collectgarbage()
    local chunk, err = loadScript(DIR .. name .. ".lua", "btc")
    if not chunk then error(err) end
    chunk = nil
    markDone(name)
    lcd.clear()
    lcd.drawText(64, 28, "PREPARING " .. np .. "/" .. #pending, CENTER)
    if np == #pending then menuMode() end
    last = getTime()
    return 0
  end
  local now = getTime()
  frameTicks = frameTicks * 0.9 + (now - last) * 0.1
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

-- use/state are for the test harness; EdgeTX only looks at init and run
return { init = init, run = run, use = use, state = function() return state end }
