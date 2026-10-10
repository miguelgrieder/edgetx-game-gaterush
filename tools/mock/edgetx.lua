-- Fake EdgeTX B&W (TX12 / PCB=X7) Lua API with firmware-accurate drawing (docs/research/lcd_semantics.md).
-- install() replaces the globals; anything not on the B&W API raises a clear error.
-- Code that runs inside the radio sandbox (lcd/io functions) uses string.x(s) calls, not s:x().
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local FB = dofile(here .. "framebuffer.lua")
local realio, realos, realLoadfile = io, os, loadfile
local W, H = 128, 64

local M = {}

local function loadFont(name) return dofile(here .. name) end
local FONTS = {
  [0] = { glyphs = loadFont("font5x7.lua"), w = 5, h = 7 },
  [0x200] = { glyphs = loadFont("font4x6.lua"), w = 5, h = 6 },
  [0x300] = { glyphs = loadFont("font8x10.lua"), w = 8, h = 12 },
  [0x400] = { glyphs = loadFont("font10x14.lua"), w = 10, h = 16 },
}

local C = {
  BLINK = 0x01, INVERS = 0x02, FORCE = 0x02, ERASE = 0x04, RIGHT = 0x04, ROUND = 0x08, LEFT = 0,
  CENTER = 0x20, BOLD = 0x40, PREC1 = 0x20, PREC2 = 0x30,
  SMLSIZE = 0x200, MIDSIZE = 0x300, DBLSIZE = 0x400, XXLSIZE = 0x500, TIMEHOUR = 0x2000,
  SOLID = 0xff, DOTTED = 0x55, PLAY_NOW = 0x10, PLAY_BACKGROUND = 0x20, LCD_W = W, LCD_H = H,
  -- TX12 key events
  EVT_VIRTUAL_ENTER = 0x22, EVT_VIRTUAL_ENTER_LONG = 0x82, EVT_VIRTUAL_EXIT = 0x21,
  EVT_VIRTUAL_PREV = 0x1003, EVT_VIRTUAL_NEXT = 0x1004, EVT_VIRTUAL_DEC = 0x1003, EVT_VIRTUAL_INC = 0x1004,
  EVT_VIRTUAL_PREV_PAGE = 0x23, EVT_VIRTUAL_NEXT_PAGE = 0x24, EVT_VIRTUAL_MENU = 0x2B,
  EVT_ENTER_FIRST = 0x62, EVT_ENTER_BREAK = 0x22, EVT_ENTER_LONG = 0x82, EVT_ENTER_REPT = 0x42,
  EVT_EXIT_BREAK = 0x21, EVT_PAGEUP_BREAK = 0x23, EVT_PAGEDN_BREAK = 0x24,
  EVT_ROT_LEFT = 0x1003, EVT_ROT_RIGHT = 0x1004,
}
M.C = C

-- globals that legitimately may be nil depending on radio/firmware version
local OPTIONAL = {
  getStickMode = true, playFile = true, EVT_ROT_BREAK = true, EVT_ROT_LONG = true,
  EVT_VIRTUAL_INC_REPT = true, EVT_VIRTUAL_DEC_REPT = true, EVT_VIRTUAL_NEXT_REPT = true,
  EVT_VIRTUAL_PREV_REPT = true, EVT_PLUS_BREAK = true, EVT_MINUS_BREAK = true,
}

local NOT_BW = {
  drawCircle = true, drawFilledCircle = true, drawBitmap = true, drawTriangle = true,
  drawFilledTriangle = true, drawArc = true, drawPie = true, drawAnnulus = true, setColor = true,
  getColor = true, RGB = true, drawHudRectangle = true, sizeText = true, invertRect = true,
}

local function bad(msg) error(msg, 3) end

local function coord(v, name)
  if type(v) ~= "number" then bad("bad argument '" .. name .. "' (number expected, got " .. type(v) .. ")") end
  if v < 0 then bad("negative coord " .. name .. "=" .. v) end
  if v ~= math.floor(v) then bad("non-integer coord " .. name .. "=" .. v) end
  return v
end

function M.install(opts)
  opts = opts or {}
  local S = {
    fb = FB.new(), clock = opts.clock or 0, inputs = { ail = 0, ele = 0, thr = 0, rud = 0 },
    tones = {}, haptics = {}, calls = 0, maxCalls = 0, sdroot = opts.sdroot, killed = {},
    lastRight = 0, lastLeft = 0, modelName = opts.modelName, modules = {}, loadModes = {}, scriptDir = opts.scriptDir,
  }
  local fb = S.fb

  local function point(x, y, att)
    if x < 0 or y < 0 or x >= W or y >= H then bad("pixel off-screen (" .. x .. "," .. y .. ") would wrap on the radio") end
    fb:mask(x, y, att)
  end

  local function hline(x, y, w, att)
    if y < 0 or y >= H or w == 0 then return end
    if w < 0 then x = x + w + 1; w = -w end
    if x + w <= 0 or x >= W then return end
    if x < 0 then w = w + x; x = 0 end
    if x + w > W then w = W - x end
    for i = 0, w - 1 do fb:mask(x + i, y, att) end
  end

  local function vline(x, y, h, att)
    if x < 0 or x >= W or h == 0 then return end
    if h < 0 then y = y + h + 1; h = -h end
    if y + h <= 0 or y >= H then return end
    if y < 0 then h = h + y; y = 0 end
    if y + h > H then h = H - y end
    for i = 0, h - 1 do fb:mask(x, y + i, att) end
  end

  local function bit(v, n) return math.floor(v / 2 ^ n) % 2 == 1 end

  local function line(x1, y1, x2, y2, pat, att)
    local dx, dy = x2 - x1, y2 - y1
    local dxabs, dyabs = math.abs(dx), math.abs(dy)
    local sdx = dx > 0 and 1 or (dx < 0 and -1 or 0)
    local sdy = dy > 0 and 1 or (dy < 0 and -1 or 0)
    local x, y = math.floor(dyabs / 2), math.floor(dxabs / 2)
    local px, py = x1, y1
    if dxabs >= dyabs then
      for _ = 0, dxabs do
        if bit(pat, px % 8) then point(px, py, att) end
        y = y + dyabs
        if y >= dxabs then y = y - dxabs; py = py + sdy end
        px = px + sdx
      end
    else
      for _ = 0, dyabs do
        if bit(pat, py % 8) then point(px, py, att) end
        x = x + dxabs
        if x >= dyabs then x = x - dyabs; px = px + sdx end
        py = py + sdy
      end
    end
  end

  -- one glyph via lcdPutPattern; returns the next x
  local function putChar(x, y, c, flags)
    local size = flags - flags % 0x100
    size = size % 0x800
    local font = FONTS[size] or FONTS[0]
    local glyph = font.glyphs[c] or font.glyphs[32]
    local inv = flags % 4 >= 2
    local h = font.h
    for i = 0, font.w + 1 do
      local col
      local skip = false
      if i == 0 then
        if x == 0 or not inv then skip = true end
      elseif i <= font.w then
        col = glyph[i]
        if col == 0xff or (type(col) == "table" and col[1] == 0xff and col[2] == 0xff) then skip = true end
      end
      if not skip then
        local px = (i == 0) and x - 1 or x
        if px >= 0 and px < W then
          for j = -1, h do
            local plot, draw = false, true
            if j < 0 or (j == h and size ~= 0x200) then
              if h >= 12 or (j < 0 and not inv) or y + j < 0 then draw = false end
            elseif col then
              local b = type(col) == "table" and (j < 8 and col[1] or col[2]) or col
              plot = bit(b, j % 8)
            end
            if draw then
              if inv then plot = not plot end
              if y + j < H then fb:mask(px, y + j, plot and 2 or 4) end
            end
          end
        end
        if i ~= 0 then x = x + 1 end
      end
    end
    return x
  end

  local function textWidth(s, flags)
    local size = (flags - flags % 0x100) % 0x800
    local font = FONTS[size] or FONTS[0]
    local w = 0
    for k = 1, #s do
      local g = font.glyphs[string.byte(s, k)] or font.glyphs[32]
      for i = 1, font.w do
        local col = g[i]
        if not (col == 0xff or (type(col) == "table" and col[1] == 0xff and col[2] == 0xff)) then w = w + 1 end
      end
      w = w + 1
    end
    return w
  end
  S.textWidth = textWidth

  local lcd = {}
  function lcd.clear() fb:clear() end
  function lcd.refresh() end
  function lcd.resetBacklightTimeout() S.backlight = (S.backlight or 0) + 1 end
  function lcd.drawPoint(x, y, flags)
    point(coord(x, "x"), coord(y, "y"), flags or 0)
  end
  function lcd.drawLine(x1, y1, x2, y2, pat, flags)
    coord(x1, "x1"); coord(y1, "y1"); coord(x2, "x2"); coord(y2, "y2")
    if type(pat) ~= "number" or type(flags) ~= "number" then bad("drawLine needs pattern and flags") end
    if x1 > W or y1 > H or x2 > W or y2 > H then
      S.dropped = (S.dropped or 0) + 1
      return
    end
    if pat == 0xff and x1 == x2 then vline(x1, math.min(y1, y2), math.abs(y2 - y1) + 1, flags)
    elseif pat == 0xff and y1 == y2 then hline(math.min(x1, x2), y1, math.abs(x2 - x1) + 1, flags)
    else line(x1, y1, x2, y2, pat, flags) end
  end
  function lcd.drawRectangle(x, y, w, h, flags)
    coord(x, "x"); coord(y, "y")
    flags = flags or 0
    vline(x, y, h, flags)
    vline(x + w - 1, y, h, flags)
    if flags % 16 < 8 then x = x + 1; w = w - 2 end
    hline(x, y + h - 1, w, flags)
    hline(x, y, w, flags)
  end
  function lcd.drawFilledRectangle(x, y, w, h, flags)
    coord(x, "x"); coord(y, "y")
    for i = y, y + h - 1 do hline(x, i, w, flags or 0) end
  end
  function lcd.drawText(x, y, s, flags)
    coord(x, "x"); coord(y, "y")
    flags = flags or 0
    s = tostring(s)
    local origX = x
    if flags % 8 >= 4 then x = x - textWidth(s, flags)
    elseif flags % 64 >= 32 then x = x - math.floor(textWidth(s, flags) / 2) end
    for k = 1, #s do x = putChar(x, y, string.byte(s, k), flags) end
    S.lastRight, S.lastLeft = x, origX
    if (flags - flags % 0x100) % 0x800 == 0x300 then S.lastRight = x + 1 end
    if flags % 8 >= 4 then S.lastLeft, S.lastRight = x - textWidth(s, flags), origX end
  end
  function lcd.drawNumber(x, y, v, flags) lcd.drawText(x, y, tostring(math.floor(v)), flags) end
  function lcd.getLastPos() return S.lastRight end
  lcd.getLastRightPos = lcd.getLastPos
  function lcd.getLastLeftPos() return S.lastLeft end
  for _, n in ipairs({ "drawTimer", "drawChannel", "drawSwitch", "drawSource", "drawGauge", "drawPixmap",
    "drawScreenTitle", "drawCombobox" }) do
    lcd[n] = function() bad("lcd." .. n .. " exists on B&W but is not implemented in the mock") end
  end
  -- fast mode (calibration): skip rasterising, keep call counting
  if opts.fast then
    for k in pairs(lcd) do
      if k:match("^draw") or k == "clear" then lcd[k] = function() end end
    end
    lcd.getLastRightPos = function() return 64 end
  end
  -- count every lcd.* call
  local counted = {}
  for k, f in pairs(lcd) do
    counted[k] = function(...)
      S.calls = S.calls + 1
      return f(...)
    end
  end
  setmetatable(counted, { __index = function(_, k)
    if NOT_BW[k] then bad("lcd." .. k .. " not available on B&W radios") end
    bad("lcd." .. tostring(k) .. " does not exist")
  end, __newindex = function(_, k) bad("cannot assign lcd." .. tostring(k)) end })

  -- EdgeTX io: io.open/read/write/close on the virtual SD
  local eio = {}
  local function sdpath(p)
    if not S.sdroot then return nil end
    return S.sdroot .. p
  end
  function eio.open(path, mode)
    local real = sdpath(path)
    if not real then return nil end
    local f = realio.open(real, string.gsub(mode or "r", "b", "") .. "b")
    if not f then return nil end
    return { f = f }
  end
  function eio.read(h, n) return h.f:read(n) or "" end
  function eio.write(h, ...)
    for _, v in ipairs({ ... }) do h.f:write(tostring(v)) end
  end
  function eio.close(h) h.f:close() end
  function eio.seek(h, n) h.f:seek("set", n) end

  local api = {
    lcd = counted,
    io = eio,
    model = { getInfo = function() return { name = S.modelName or "" } end },
    getTime = function() return S.clock end,
    getValue = function(src)
      if S.inputs[src] == nil then return nil end
      return S.inputs[src]
    end,
    getFieldInfo = function(n) return { id = n, name = n } end,
    playTone = function(f, d, p, flags)
      assert(type(f) == "number" and type(d) == "number" and type(p) == "number", "playTone(freq, len, pause [,flags])")
      if f < 150 or f > 15000 then bad("playTone frequency out of range: " .. f) end
      S.tones[#S.tones + 1] = { t = S.clock, f = f, d = d, flags = flags }
    end,
    playHaptic = function(d, p, flags)
      assert(type(d) == "number" and type(p) == "number", "playHaptic(len, pause [,flags])")
      S.haptics[#S.haptics + 1] = { t = S.clock, d = d, flags = flags }
    end,
    getUsage = function() return 0 end,
    killEvents = function(e) S.killed[#S.killed + 1] = e end,
    getStickMode = opts.stickMode and function() return opts.stickMode end or nil,
    -- loadScript(path, mode): "/SCRIPTS/TOOLS/GATERUSH/x.lua" is read from S.scriptDir (src/ or dist/...);
    -- modes are recorded in S.loadModes
    loadScript = function(path, mode)
      S.loadModes[#S.loadModes + 1] = tostring(string.match(path, "([%w_]+)%.lua$")) .. ":" .. tostring(mode)
      local dir = S.scriptDir or S.sdroot .. "/SCRIPTS/TOOLS/GATERUSH/"
      local name = string.match(path, "^/SCRIPTS/TOOLS/GATERUSH/([%w_]+)%.lua$")
      if not name then return nil, "loadScript(\"" .. tostring(path) .. "\") error: File not found" end
      local f, err = realLoadfile(dir .. name .. ".lua")
      if not f then return nil, err end
      S.loads = (S.loads or 0) + 1
      return function(...)
        local m = f(...)
        S.modules[name] = m
        return m
      end
    end,
  }
  for k, v in pairs(C) do api[k] = v end
  if opts.noLegacy then
    for _, k in ipairs({ "EVT_ENTER_BREAK", "EVT_ENTER_LONG", "EVT_EXIT_BREAK", "EVT_ROT_LEFT", "EVT_ROT_RIGHT" }) do api[k] = nil end
  end
  for k, v in pairs(api) do rawset(_G, k, v) end
  for k in pairs(OPTIONAL) do if api[k] == nil then rawset(_G, k, nil) end end

  setmetatable(_G, {
    __index = function(_, k)
      if OPTIONAL[k] or (opts.noLegacy and type(k) == "string" and string.match(k, "^EVT_")) then return nil end
      error("global '" .. tostring(k) .. "' does not exist in the EdgeTX B&W API", 2)
    end,
    __newindex = function(_, k) error("script tried to create global '" .. tostring(k) .. "'", 2) end,
  })

  -- per-frame helpers
  function S.frame()
    if S.calls > S.maxCalls then S.maxCalls = S.calls end
    local n = S.calls
    S.calls = 0
    return n
  end
  function S.stats() return { calls = S.calls, maxCalls = S.maxCalls, tones = #S.tones, haptics = #S.haptics } end
  S.realio, S.realos = realio, realos
  M.S = S
  return S
end

-- create a directory tree (works on Windows cmd and POSIX shells)
function M.mkdirp(path)
  if package.config:sub(1, 1) == "\\" then
    realos.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    realos.execute('mkdir -p "' .. path .. '"')
  end
end

-- fresh virtual SD with the GATERUSH save folder
function M.sd(name, withFolder)
  local root = "out/sd/" .. name
  if package.config:sub(1, 1) == "\\" then
    realos.execute('rmdir /s /q "' .. root:gsub("/", "\\") .. '" 2>nul')
  else
    realos.execute('rm -rf "' .. root .. '"')
  end
  M.mkdirp(root .. "/SCRIPTS/TOOLS")
  if withFolder ~= false then M.mkdirp(root .. "/SCRIPTS/TOOLS/GATERUSH") end
  return root
end

M.FB = FB
return M
