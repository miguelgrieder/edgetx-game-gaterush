local T = dofile("tests/t.lua")

local function setup()
  local h = T.H.new({ sd = "t_draw" })
  lcd.clear()
  return h, require("draw")
end

T.test("quad sprite matches mockup sprite #1", function()
  local h, draw = setup()
  draw.quad(20, 20)
  T.eq(T.region(h.fb(), 16, 16, 9, 9), T.read("tests/golden/quad_sprite1.txt"))
end)

T.test("crash sprite matches renderer quad(crash=True) and clears what is under it", function()
  local h, draw = setup()
  draw.quad(20, 20, true)
  T.eq(T.region(h.fb(), 16, 16, 9, 9), T.read("tests/golden/quad_crash.txt"))
  lcd.drawFilledRectangle(10, 10, 30, 30, FORCE)
  draw.quad(20, 20, true)
  T.eq(T.region(h.fb(), 18, 18, 5, 5), "#...#\n.#.#.\n.....\n.#.#.\n#...#\n")
end)

T.test("title icon matches renderer quad_icon()", function()
  local h, draw = setup()
  draw.quadIcon(20, 20)
  T.eq(T.region(h.fb(), 14, 14, 13, 13), T.read("tests/golden/quad_icon.txt"))
end)

T.test("3x5 font: glyph rects rebuild the bitmaps", function()
  local h, draw = setup()
  draw.glyph(draw.small["0"], 0, 0)
  draw.glyph(draw.small["7"], 4, 0)
  draw.glyph(draw.small[":"], 8, 0)
  local want = ("111.111....\n101.001..1.\n101.001....\n101.001..1.\n111.001....\n"):gsub("1", "#"):gsub("0", ".")
  T.eq(T.region(h.fb(), 0, 0, 11, 5), want)
  for d = 0, 9 do T.ok(#draw.digit3[d] >= 4 and #draw.digit3[d] % 4 == 0, "digit " .. d) end
end)

T.test("countdown digits are the 3x5 font scaled x4", function()
  local h, draw = setup()
  draw.glyph(draw.big[1], 0, 0)
  local r = T.region(h.fb(), 0, 0, 12, 20)
  T.eq(r:sub(1, 13), "....####....\n")
  T.eq(r:sub(13 * 16 + 1, 13 * 17), "############\n")
end)

T.test("tail dither patterns: 50/25/12 % along the major axis", function()
  local h, draw = setup()
  T.eq(draw.PAT[0], SOLID)
  for age = 1, 3 do draw.line(0, age, 31, age, draw.PAT[age]) end
  local n = {}
  for age = 1, 3 do
    n[age] = 0
    for x = 0, 31 do n[age] = n[age] + h.fb():get(x, age) end
  end
  T.eq(n[1], 16) T.eq(n[2], 8) T.eq(n[3], 4)
end)

T.test("draw.line drops lines with off-screen endpoints instead of sending them", function()
  local h, draw = setup()
  T.eq(draw.line(-1, 0, 10, 10, SOLID), false)
  T.eq(draw.line(0, 0, 128, 10, SOLID), false)
  T.eq(draw.line(0, 0, 10, 64, SOLID), false)
  T.eq(draw.line(0, 0, 127, 63, SOLID), true)
  T.eq(h.fb():get(127, 63), 1)
end)

T.test("mock rejects APIs that do not exist on B&W radios", function()
  setup()
  T.fails(function() lcd.drawCircle(10, 10, 5) end, "not available on B&W")
  T.fails(function() lcd.drawLine(-1, 0, 5, 5, SOLID, FORCE) end, "negative coord")
  T.fails(function() lcd.drawLine(0, 0, 5, 5) end, "pattern and flags")
  T.fails(function() return GREY_DEFAULT end, "does not exist")
end)

T.test("default drawFilledRectangle inverts (XOR) like the firmware", function()
  local h = setup()
  lcd.drawPoint(5, 5, FORCE)
  lcd.drawFilledRectangle(0, 0, 10, 10)
  T.eq(h.fb():get(5, 5), 0)
  T.eq(h.fb():get(4, 4), 1)
end)

T.test("skins: 8 designs, both frames rebuild from rects, props spin on frame 2", function()
  local h, draw = setup()
  T.eq(draw.SKIN_COUNT, 8)
  local differ = 0
  for n = 1, 8 do
    lcd.clear()
    draw.skin(n, 20, 20, 1)
    local a = T.region(h.fb(), 16, 16, 9, 9)
    lcd.clear()
    draw.skin(n, 20, 20, 2)
    local b = T.region(h.fb(), 16, 16, 9, 9)
    if a ~= b then differ = differ + 1 end
    T.ok(a:find("#"), "skin " .. n .. " empty")
  end
  T.ok(differ >= 4, "animated skins: " .. differ)
  lcd.clear()
  draw.skin(1, 20, 20, 1)
  T.eq(T.region(h.fb(), 16, 16, 9, 9), T.read("tests/golden/quad_sprite1.txt"))
  -- a skin clears the tunnel lines under its disc
  lcd.clear()
  lcd.drawFilledRectangle(10, 10, 20, 20, FORCE)
  draw.skin(2, 20, 20, 1)
  T.eq(h.fb():get(18, 18), 0)
end)
