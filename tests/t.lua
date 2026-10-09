-- Minimal test runner: T.test(name, fn); T.eq(a, b, msg); T.run() -> failures
if package.loaded.gaterush_t then return package.loaded.gaterush_t end
local T = { list = {} }
package.loaded.gaterush_t = T
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
T.H = dofile(here .. "../tools/harness.lua")

function T.test(name, fn) T.list[#T.list + 1] = { name, fn } end
function T.eq(a, b, msg)
  if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function T.ok(v, msg) if not v then error(msg or "assertion failed", 2) end end
function T.near(a, b, eps, msg)
  if math.abs(a - b) > (eps or 1e-6) then error((msg or "") .. " expected ~" .. b .. ", got " .. a, 2) end
end
function T.fails(fn, pattern)
  local ok, err = pcall(fn)
  if ok then error("expected an error", 2) end
  if pattern and not tostring(err):find(pattern) then error("wrong error: " .. tostring(err), 2) end
end

-- read a text file with the real io (the mock replaces the global one)
function T.read(path)
  local f = T.H.mock.S and T.H.mock.S.realio.open(path, "rb") or io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"):gsub("\r\n", "\n")
  f:close()
  return s
end

-- region of the framebuffer as '#'/'.' rows
function T.region(fb, x0, y0, w, h)
  local rows = {}
  for y = y0, y0 + h - 1 do
    local r = {}
    for x = x0, x0 + w - 1 do r[#r + 1] = fb:get(x, y) == 1 and "#" or "." end
    rows[#rows + 1] = table.concat(r)
  end
  return table.concat(rows, "\n") .. "\n"
end

function T.run(file)
  local fails = 0
  for _, t in ipairs(T.list) do
    local ok, err = pcall(t[2])
    if not ok then
      fails = fails + 1
      print("  FAIL " .. file .. " :: " .. t[1] .. "\n       " .. tostring(err))
    end
  end
  print(string.format("%-18s %d/%d passed", file, #T.list - fails, #T.list))
  T.list = {}
  return fails
end

return T
