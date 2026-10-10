-- Things learned on real radios / the firmware (see docs/DECISIONS.md)
local T = dofile("tests/t.lua")

local DIR = "/SCRIPTS/TOOLS/GATERUSH/"

T.test("after an update each module is recompiled once, so an old .luac can't outlive it", function()
  local B, C = DIR .. "build.txt", DIR .. "compiled.txt"
  local function modes(h)
    h.use("game") -- the play group too
    local all, seen = {}, {}
    for _, m in ipairs(h.S.loadModes) do
      local name, mode = m:match("^(.-):(.*)$")
      if not seen[name] then seen[name] = true; all[#all + 1] = mode end
    end
    return all
  end
  local h = T.H.new({ sd = "t_stamp", files = { [B] = "v9-1\n" } })
  local m = modes(h)
  T.ok(#m >= 8, "modules loaded: " .. #m)
  for _, v in ipairs(m) do T.eq(v, "btc") end
  local f = h.S.realio.open(h.S.sdroot .. C, "rb")
  local done = f:read("*a")
  f:close()
  T.ok(done:find("^v9%-1\n") and done:find("\ngame\n"), "compiled.txt: " .. done)
  -- next start, same build: the .luac files are used
  local h2 = T.H.new({ sd = "t_stamp2", files = { [B] = "v9-1\n", [C] = done } })
  for _, v in ipairs(modes(h2)) do T.eq(v, "bt") end
  -- a new build: recompiled again
  local h3 = T.H.new({ sd = "t_stamp3", files = { [B] = "v9-2\n", [C] = done } })
  for _, v in ipairs(modes(h3)) do T.eq(v, "btc") end
  -- no build file (running from src/): plain loads
  local h4 = T.H.new({ sd = "t_stamp4" })
  for _, v in ipairs(modes(h4)) do T.eq(v, "bt") end
end)

-- EdgeTX 2.12.2's Lua floors a float before == / ~= against an integer (0.87 ~= 0 is false; fixed in
-- 2.12.4) and the PC's Lua 5.2 can't show it, so the drawing and game modules may compare with a number
-- literal only where both sides are integers, marked "int" in a comment
T.test("track/draw/game/fx never compare a float with == / ~= against a number (EdgeTX 2.12.2 Lua bug)", function()
  for _, name in ipairs({ "track", "draw", "game", "fx" }) do
    local n = 0
    for line in (T.read("src/" .. name .. ".lua"):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
      n = n + 1
      local code, comment = line:match("^(.-)%-%-(.*)$")
      code, comment = code or line, comment or ""
      if code:find("[=~]=%s*%-?%d") and not comment:find("int") then
        error(name .. ".lua:" .. n .. ": == / ~= with a number literal: " .. line)
      end
    end
  end
end)

T.test("DEBUG shows the frame rate and the Lua memory while playing", function()
  local function play(cfg)
    local h = T.H.new({ sd = "t_debug", files = { [DIR .. "gaterush.cfg"] = cfg } })
    h.wait(19)
    h.step(0, 0, 0, 0, "enter") -- title -> center sticks; then the countdown with the sticks centered
    h.wait(90)
    T.ok(h.app.state() >= 5, "in the countdown or playing: " .. h.app.state())
    return T.region(h.fb(), 10, 56, 40, 8)
  end
  T.ok(play("DEBUG=1\n") ~= play("DEBUG=0\n"), "bottom-left readout")
end)
