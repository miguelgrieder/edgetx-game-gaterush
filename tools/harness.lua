-- Loads GateRush (src modules or the built file) on top of the mock and steps it frame by frame.
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local mock = dofile(here .. "mock/edgetx.lua")

local H = {}
H.mock = mock
H.MODULES = { "config", "stats", "draw", "input", "track", "fx", "game", "screens", "main" }

local EVENTS = {
  enter = "EVT_VIRTUAL_ENTER", long = "EVT_VIRTUAL_ENTER_LONG", exit = "EVT_VIRTUAL_EXIT",
  next = "EVT_VIRTUAL_NEXT", prev = "EVT_VIRTUAL_PREV",
}

-- opts: target ("src" | "dist"), sd (name), noSaveFolder, stickMode, modelName, noLegacy
function H.new(opts)
  opts = opts or {}
  local sdroot = mock.sd(opts.sd or "default", not opts.noSaveFolder)
  local S = mock.install({ sdroot = sdroot, stickMode = opts.stickMode, modelName = opts.modelName or "",
    noLegacy = opts.noLegacy, clock = opts.clock or 1000, fast = opts.fast })
  local h = { S = S, frame = 0, lastCalls = 0 }
  -- libraries a tool script does not get on the radio (verified in the firmware simulator)
  local HIDDEN = { "table", "os", "debug", "coroutine" }
  local saved = {}
  local function radio(f, ...)
    for _, k in ipairs(HIDDEN) do saved[k] = rawget(_G, k); rawset(_G, k, nil) end
    local ok, r = pcall(f, ...)
    for _, k in ipairs(HIDDEN) do rawset(_G, k, saved[k]) end
    if not ok then error(r, 0) end
    return r
  end
  h.radio = radio
  if (opts.target or "src") == "dist" then
    h.app = radio(dofile, "dist/SCRIPTS/TOOLS/gaterush.lua")
  else
    if not package.path:find("src/?.lua", 1, true) then package.path = "src/?.lua;" .. package.path end
    for _, m in ipairs(H.MODULES) do package.loaded[m] = nil end
    h.app = radio(require, "main")
    h.game, h.input, h.track, h.config, h.stats = require("game"), require("input"), require("track"),
      require("config"), require("stats")
  end
  if opts.setup then opts.setup(h) end
  radio(h.app.init)

  -- advance one frame (5 ticks = 50 ms) with the given sticks and event name/number
  function h.step(ail, ele, thr, rud, ev, ticks)
    S.clock = S.clock + (ticks or 5)
    S.inputs.ail, S.inputs.ele, S.inputs.thr, S.inputs.rud = ail or 0, ele or 0, thr or 0, rud or 0
    if type(ev) == "string" then ev = _G[EVENTS[ev] or ev] end
    h.frame = h.frame + 1
    h.ret = radio(h.app.run, ev or 0)
    h.lastCalls = S.frame()
    return h.ret
  end

  -- idle frames
  function h.wait(n, ail, ele, thr, rud)
    for _ = 1, n do h.step(ail, ele, thr, rud) end
  end

  function h.fb() return S.fb end
  return h
end

return H
