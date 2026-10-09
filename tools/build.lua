-- Builds the SD card image in dist/: src/main.lua becomes SCRIPTS/TOOLS/gaterush.lua (with the TOOLS
-- header) and every other module goes to SCRIPTS/TOOLS/GATERUSH/<name>.lua, loaded at runtime with
-- loadScript. Each file compiles on its own on the radio.
local MODULES = { "config", "input", "stats", "menus", "draw", "fx", "track", "game" }
local OUT = "dist/SCRIPTS/TOOLS/"

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a"):gsub("\r\n", "\n")
  f:close()
  return s
end

local function write(path, text)
  assert((loadstring or load)(text, "=" .. path))
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
  print(string.format("built %-40s %6d bytes", path, #text))
end

local main = read("src/main.lua")
assert(main:match("return { init = init, run = run"), "main.lua must return the script interface")
write(OUT .. "gaterush.lua", "-- TNS|GateRush|TNE\n-- GateRush (generated from src/ by tools/build.lua; edit the sources)\n" .. main)
for _, name in ipairs(MODULES) do
  local src = read("src/" .. name .. ".lua")
  assert(not src:find("require%("), name .. ": use use(), not require()")
  write(OUT .. "GATERUSH/" .. name .. ".lua", src)
end
