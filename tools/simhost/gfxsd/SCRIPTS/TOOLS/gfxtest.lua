-- TNS|GfxTest|TNE
-- Draws the primitives GateRush relies on, to compare the real firmware with the mock pixel by pixel.
local function run()
  lcd.clear()
  -- tunnel-like diagonals with the fade patterns, both major axes and both directions
  local pats = { 0xff, 0x55, 0x11, 0x01 }
  for i = 1, 4 do
    local p = pats[i]
    lcd.drawLine(2 + i * 6, 2, 12 + i * 6, 20, p, FORCE)
    lcd.drawLine(30 + i * 6, 20, 40 + i * 6, 14, p, FORCE)
    lcd.drawLine(2, 22 + i * 3, 60, 24 + i * 3, p, FORCE)
    lcd.drawLine(66 + i * 3, 2, 66 + i * 3, 30, p, FORCE)
  end
  -- quad sprite (normal) and crash sprite over a black block
  local function disc(x, y, f)
    lcd.drawFilledRectangle(x - 4, y - 1, 9, 3, f)
    lcd.drawFilledRectangle(x - 3, y - 3, 7, 2, f)
    lcd.drawFilledRectangle(x - 3, y + 2, 7, 2, f)
    lcd.drawFilledRectangle(x - 1, y - 4, 3, 1, f)
    lcd.drawFilledRectangle(x - 1, y + 4, 3, 1, f)
  end
  disc(90, 10, FORCE)
  lcd.drawLine(87, 7, 93, 13, SOLID, ERASE)
  lcd.drawLine(87, 13, 93, 7, SOLID, ERASE)
  lcd.drawPoint(90, 10, FORCE)
  lcd.drawFilledRectangle(100, 2, 20, 20, FORCE)
  disc(110, 12, ERASE)
  lcd.drawLine(114, 13, 111, 16, SOLID, FORCE)
  lcd.drawLine(108, 10, 112, 14, SOLID, FORCE)
  -- XOR fill over text, rectangles, dotted rule, small and double text
  lcd.drawText(4, 40, "XOR TEST", 0)
  lcd.drawFilledRectangle(2, 38, 50, 11)
  lcd.drawRectangle(60, 36, 30, 12, FORCE)
  lcd.drawLine(8, 52, 119, 52, DOTTED, FORCE)
  lcd.drawText(64, 54, "CENTER 0:12", CENTER)
  lcd.drawText(96, 36, "Ab", DBLSIZE)
  return 0
end
return { run = run }
