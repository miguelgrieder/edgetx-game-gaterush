-- Loads GateRush (src modules or the built file) on top of the mock and steps it frame by frame.
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local mock = dofile(here .. "mock/edgetx.lua")

local H = {}
H.mock = mock
H.MODULES = { "config", "stats", "draw", "input", "track", "fx", "game", "menus" }

local EVENTS = {
  enter = "EVT_VIRTUAL_ENTER", long = "EVT_VIRTUAL_ENTER_LONG", exit = "EVT_VIRTUAL_EXIT",
  next = "EVT_VIRTUAL_NEXT", prev = "EVT_VIRTUAL_PREV",
}

-- opts: target ("src" | "dist"), sd (name), noSaveFolder, stickMode, modelName, noLegacy
function H.new(opts)
  opts = opts or {}
  local sdroot = mock.sd(opts.sd or "default", not opts.noSaveFolder)
  local dist = (opts.target or "src") == "dist"
  local S = mock.install({ sdroot = sdroot, stickMode = opts.stickMode, modelName = opts.modelName or "",
    noLegacy = opts.noLegacy, clock = opts.clock or 1000, fast = opts.fast,
    scriptDir = dist and "dist/SCRIPTS/TOOLS/GATERUSH/" or "src/" })
  local h = { S = S, frame = 0, lastCalls = 0 }
  -- libraries a tool script does not get on the radio (verified in the firmware simulator)
  local HIDDEN = { "table", "os", "debug", "coroutine" }
  local saved = {}
  -- EdgeTX does not set the string metatable: ("x"):sub() fails on the radio
  local smeta = getmetatable("")
  local function radio(f, ...)
    for _, k in ipairs(HIDDEN) do saved[k] = rawget(_G, k); rawset(_G, k, nil) end
    local sidx = smeta.__index
    smeta.__index = nil
    local ok, r = pcall(f, ...)
    smeta.__index = sidx
    for _, k in ipairs(HIDDEN) do rawset(_G, k, saved[k]) end
    if not ok then error(r, 0) end
    return r
  end
  h.radio = radio
  h.app = radio(dofile, dist and "dist/SCRIPTS/TOOLS/gaterush.lua" or "src/main.lua")
  -- h.game, h.config, ...: the module as the game's own loader has it (loading it if needed)
  function h.use(name) return radio(h.app.use, name) end
  setmetatable(h, { __index = function(_, k)
    for _, m in ipairs(H.MODULES) do if m == k then return h.use(k) end end
  end })
  -- context for input scripts / bots: always the current module instances
  h.ctx = setmetatable({ h = h }, { __index = function(_, k) return h[k] end })
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
