-- Golden masters: the last frame of each inputs/NN_*.lua scenario must match tests/golden/NN_*.pbm.
-- APPROVE=1 lua5.2 tests/run_all.lua test_screens   rewrites the goldens (review the PNGs first!)
local T = dofile("tests/t.lua")
local FB = T.H.mock.FB

local SCREENS = { "00_rf_warning", "01_title", "02_center_sticks", "03_countdown", "04_play_start",
  "05_play_out_tolerance", "06_play_final", "07_pause", "08_resume_countdown", "09_crashed",
  "10_settings_p1", "11_settings_p2" }
local approve = os.getenv("APPROVE") == "1"

local function render(name, target)
  local sc = dofile("inputs/" .. name .. ".lua")
  local h = T.H.new({ target = target, sd = "golden_" .. name, setup = sc.setup })
  local ctx = { game = h.game, input = h.input, track = h.track, h = h }
  local maxCalls = 0
  for f = 1, sc.frames do
    h.step(sc.fn(f, h.S.clock + 5, ctx))
    if h.lastCalls > maxCalls then maxCalls = h.lastCalls end
  end
  return h.fb(), maxCalls, sc
end

local function save(path, text)
  local f = assert(T.H.mock.S.realio.open(path, "wb"))
  f:write(text)
  f:close()
end

T.H.mock.mkdirp("out/screens")
for _, name in ipairs(SCREENS) do
  T.test(name .. " matches its golden", function()
    local fb, calls = render(name, "src")
    T.ok(calls <= 300, "draw calls " .. calls)
    save("out/screens/" .. name .. ".pbm", fb:pbm())
    local golden = "tests/golden/" .. name .. ".pbm"
    local want = T.read(golden)
    if approve or not want then
      save(golden, fb:pbm())
      if not approve then error("new golden written: " .. golden .. " (review it, then rerun)") end
      return
    end
    local g = FB.fromPbm(want)
    if not g:equals(fb) then
      os.execute("python tools/snapshot.py diff " .. golden .. " out/screens/" .. name .. ".pbm out/screens/"
        .. name .. "_diff.png")
      error(g:diffCount(fb) .. " pixels differ, see out/screens/" .. name .. "_diff.png")
    end
  end)
end

-- the built single file must draw exactly the same (catches concatenation/scope bugs)
for _, name in ipairs(SCREENS) do
  if not dofile("inputs/" .. name .. ".lua").target then
    T.test(name .. " from dist/ matches too", function()
      local fb = render(name, "dist")
      T.ok(FB.fromPbm(T.read("tests/golden/" .. name .. ".pbm")):equals(fb), "dist differs from golden")
    end)
  end
end
