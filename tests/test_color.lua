-- src/color.lua on a fake 480x320 colour screen (TX15): the 128x64 game scaled x3 and centred, in black on white
local T = dofile("tests/t.lua")

T.test("colour screens: the game is scaled x3 and centred, FORCE/ERASE draw black/white, XOR fills invert", function()
  local calls = {}
  local function rec(name) return function(...) calls[#calls + 1] = { name, ... } end end
  local fake = { drawLine = rec("line"), drawFilledRectangle = rec("fill"), drawRectangle = rec("rect"),
    drawText = rec("text"), drawNumber = rec("number"), invertRect = rec("invert"), clear = rec("clear"),
    resetBacklightTimeout = rec("backlight"),
    RGB = function(r) return r > 0 and 0x7FFF0000 or 0x10000 end, -- white, black
    sizeText = function(s) return 10 * #s, 20 end }
  local env = setmetatable({ lcd = fake, LCD_W = 480, LCD_H = 320, SMLSIZE = 0x300, MIDSIZE = 0x400,
    DBLSIZE = 0x500, XXLSIZE = 0x600 }, { __index = _G })
  assert(loadfile("src/color.lua", "t", env))()
  local lcd, BLACK, WHITE = env.lcd, 0x10000, 0x7FFF0000
  T.eq(env.LCD_W, 128) T.eq(env.LCD_H, 64) -- the game keeps drawing for 128x64
  lcd.drawLine(0, 0, 127, 63, 0xff, env.FORCE)
  T.eq(table.concat(calls[1], " ", 2), table.concat({ 49, 65, 430, 254, 0xff, BLACK }, " ")) -- x0 48, y0 64, +1 mid
  lcd.drawFilledRectangle(1, 2, 3, 4, env.ERASE)
  T.eq(table.concat(calls[2], " "), table.concat({ "fill", 51, 70, 9, 12, WHITE }, " "))
  lcd.drawFilledRectangle(1, 2, 3, 4) -- B&W XOR
  T.eq(calls[3][1], "invert")
  lcd.drawText(10, 5, "AB", env.SMLSIZE)
  T.eq(calls[4][5], 0x400 + BLACK) -- small -> MIDSIZE
  T.eq(lcd.getLastRightPos(), 10 + 20 / 3) -- right edge back in game pixels
  lcd.resetBacklightTimeout()
  T.eq(calls[5][1], "backlight") -- not wrapped: passed through
end)
