-- Best/average time per difficulty key, persisted as "key best count avg_ms" lines.
local M = {}

M.FILE = "/SCRIPTS/TOOLS/GATERUSH/gaterush.dat"
M.rec = {} -- key -> { best_ms, count, avg_ms }

function M.parse(text)
  for k, b, c, a in string.gmatch(text, "(%w+) (%d+) (%d+) (%d+)") do
    M.rec[k] = { tonumber(b), tonumber(c), tonumber(a) }
  end
end

function M.load()
  M.rec = {}
  local f = io.open(M.FILE, "r")
  if not f then return end
  local text = "" -- no table library in EdgeTX tool scripts
  repeat
    local chunk = io.read(f, 256)
    if chunk then text = text .. chunk end
  until not chunk or #chunk < 256
  io.close(f)
  M.parse(text)
end

function M.save()
  local f = io.open(M.FILE, "w")
  if not f then return false end
  for k, r in pairs(M.rec) do
    io.write(f, k, " ", r[1], " ", r[2], " ", r[3], "\n")
  end
  io.close(f)
  return true
end

function M.best(key)
  local r = M.rec[key]
  return r and r[1]
end

function M.avg(key)
  local r = M.rec[key]
  return r and r[3]
end

-- record a finished run; returns true when it is a new best
function M.add(key, ms)
  ms = math.floor(ms)
  local r = M.rec[key]
  if not r then
    M.rec[key] = { ms, 1, ms }
    return true
  end
  local isBest = ms > r[1]
  if isBest then r[1] = ms end
  r[3] = math.floor((r[3] * r[2] + ms) / (r[2] + 1) + 0.5)
  r[2] = r[2] + 1
  return isBest
end

function M.reset(key) M.rec[key] = nil end

-- "m:ss" or "--:--"
function M.fmt(ms)
  if not ms then return "--:--" end
  local s = math.floor(ms / 1000)
  local ss = s % 60
  return math.floor(s / 60) .. ":" .. (ss < 10 and "0" or "") .. ss
end

return M
