-- lua5.2 tests/run_all.lua [name ...]  (run from the repo root)
local T = dofile("tests/t.lua")
local files = { "test_draw", "test_config", "test_stats", "test_input", "test_track", "test_rules", "test_firmware",
  "test_screens" }
if arg[1] then files = arg end
local fails = 0
for _, f in ipairs(files) do
  local ok, err = pcall(dofile, "tests/" .. f .. ".lua")
  if not ok then
    print("  ERROR loading " .. f .. ": " .. tostring(err))
    fails = fails + 1
  else
    fails = fails + T.run(f)
  end
end
print(fails == 0 and "ALL TESTS PASSED" or (fails .. " FAILURE(S)"))
os.exit(fails == 0 and 0 or 1)
