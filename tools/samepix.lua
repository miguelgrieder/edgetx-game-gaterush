-- lua5.2 tools/samepix.lua <out.txt>: replays every scenario in inputs/ (the bot plays deterministically) and
-- writes a checksum of the screen for every frame. Run it on two versions and diff the files: a speed
-- change must not change a single pixel (nor the game, which would change the frames that follow).
local out = assert(io.open(arg[1], "wb"))
local H = dofile("tools/harness.lua")
local NAMES = { "01_title", "02_center_sticks", "03_countdown", "04_play_start", "05_play_out_tolerance", "06_play_final",
  "07_pause", "08_resume_countdown", "09_crashed", "10_settings_p1", "11_settings_p2", "12_settings_p3", "13_scroll",
  "14_coupled", "15_sprint_finish", "16_zen", "17_wreck", "18_practice_left", "19_skins", "20_stop_reverse",
  "perf_worst" }
for _, name in ipairs(NAMES) do
  local sc = dofile("inputs/" .. name .. ".lua")
  local h = H.new({ sd = "samepix", setup = sc.setup })
  for f = 1, sc.frames do
    h.step(sc.fn(f, h.S.clock + 5, h.ctx))
    local s = h.fb():pbm()
    local sum = 0
    for i = 1, #s do sum = (sum * 31 + s:byte(i)) % 4294967296 end
    out:write(string.format("%s %d %08x\n", name, f, sum))
  end
end
out:close()
