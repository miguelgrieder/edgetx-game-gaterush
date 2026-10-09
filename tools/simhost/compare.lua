-- lua5.2 tools/simhost/compare.lua <sim_frames_dir> [<dir> ...]
-- Renders reference screens in the mock (same firmware-like state as tools/simhost/inputs/*.txt) and
-- looks for a pixel-identical frame among the PBMs captured from the real firmware.
-- Any screen without an exact match is a mock (or game timing) divergence to investigate.
local H = dofile("tools/harness.lua")
local FB = H.mock.FB
local realio = io

local dirs = { ... }
assert(#dirs > 0, "usage: compare.lua out/simu/play out/simu/settings")

-- every frame captured from the firmware
local frames = {}
for _, d in ipairs(dirs) do
  for i = 1, 2000 do
    local f = realio.open(string.format("%s/frame_%04d.pbm", d, i), "rb")
    if not f then break end
    frames[#frames + 1] = { name = d .. "#" .. i, fb = FB.fromPbm(f:read("*a")) }
    f:close()
  end
end

-- reference screens: sequence of {frames, event} steps on the mock with the simulator's radio setup
local REFS = {
  { "warning (model name)", { { 5 } } },
  { "title (no best)", { { 10 }, { 1, "enter" }, { 10 } } },
  { "settings p1, CRASH DELAY selected", { { 10 }, { 1, "enter" }, { 10 }, { 1, "long" }, { 1, "enter" }, { 8 }, { 1, "next" } } },
  { "settings p1, editing <0.4 S>", { { 10 }, { 1, "enter" }, { 10 }, { 1, "long" }, { 1, "enter" }, { 8 }, { 1, "next" },
    { 1, "enter" }, { 1, "next" } } },
  { "settings p2, TRACK LEN", { { 10 }, { 1, "enter" }, { 10 }, { 1, "long" }, { 1, "enter" }, { 8 },
    { 1, "next" }, { 1, "enter" }, { 1, "next" }, { 1, "enter" }, { 1, "next" }, { 1, "next" }, { 1, "next" }, { 1, "next" } } },
  { "center sticks, both bars full", { { 10 }, { 1, "enter" }, { 10 }, { 1, "enter" }, { 9 } } },
}

local out = io.stdout
local fails = 0

-- the graphics self-test tool (tools/simhost/gfxsd) rendered by the mock
do
  H.mock.install({})
  local tool = dofile("tools/simhost/gfxsd/SCRIPTS/TOOLS/gfxtest.lua")
  tool.run(0)
  local fb = H.mock.S.fb
  local best, bestName = 1e9, "-"
  for _, fr in ipairs(frames) do
    local d = fr.fb:diffCount(fb)
    if d < best then best, bestName = d, fr.name end
  end
  if best > 0 then fails = fails + 1 end
  out:write(string.format("%-40s %s (closest firmware frame %s, %d px differ)\n", "gfx self-test (lines, patterns, sprites)",
    best == 0 and "IDENTICAL" or "DIFFERS", bestName, best))
  if best > 0 then
    local f = H.mock.S.realio.open("out/compare_gfx.pbm", "wb")
    f:write(fb:pbm())
    f:close()
  end
end
for _, ref in ipairs(REFS) do
  local h = H.new({ sd = "compare", modelName = "MODEL01", stickMode = 1 })
  for _, s in ipairs(ref[2]) do
    for _ = 1, s[1] do h.step(0, 0, 0, 0, s[2]) end
  end
  local best, bestName = 1e9, "-"
  for _, fr in ipairs(frames) do
    local d = fr.fb:diffCount(h.fb())
    if d < best then best, bestName = d, fr.name end
  end
  if best > 0 then fails = fails + 1 end
  out:write(string.format("%-40s %s (closest firmware frame %s, %d px differ)\n", ref[1],
    best == 0 and "IDENTICAL" or "DIFFERS", bestName, best))
  if best > 0 then
    local f = h.S.realio.open("out/compare_" .. ref[1]:gsub("%W+", "_") .. ".pbm", "wb")
    f:write(h.fb():pbm())
    f:close()
  end
end
os.exit(fails == 0 and 0 or 1)
