-- Drawing primitives built only from the B&W lcd.* calls (no circles, no bitmaps).
local M = {}

-- glyph bitmaps (rows) -> flat rect lists {x, y, w, h, ...}: one rect per run, runs merged downwards
-- (string.sub, not row:sub: EdgeTX does not set the string metatable)
local function rects(rows, scale)
  local out, open = {}, {} -- open[x0 * 16 + x1] = top row of a run still growing downwards
  local sub = string.sub
  for y = 1, #rows + 1 do
    local row, runs = rows[y] or "", {}
    local x = 1
    while x <= #row do
      if sub(row, x, x) == "1" or sub(row, x, x) == "#" then
        local x2 = x
        while sub(row, x2 + 1, x2 + 1) == "1" or sub(row, x2 + 1, x2 + 1) == "#" do x2 = x2 + 1 end
        runs[x * 16 + x2] = true
        x = x2 + 1
      else
        x = x + 1
      end
    end
    for key, top in pairs(open) do
      if not runs[key] then
        local x0, x1 = math.floor(key / 16), key % 16
        local n = #out
        out[n + 1], out[n + 2], out[n + 3], out[n + 4] = (x0 - 1) * scale, top * scale, (x1 - x0 + 1) * scale,
          (y - 1 - top) * scale
        open[key] = nil
      end
    end
    for key in pairs(runs) do
      if not open[key] then open[key] = y - 1 end
    end
  end
  return out
end
M.rects = rects

-- 3x5 HUD font (from the mockup renderer)
local F3 = {
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "001", "001", "001" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
  [":"] = { "000", "010", "000", "010", "000" }, ["%"] = { "101", "001", "010", "100", "101" },
}
M.small = {}
for k, rows in pairs(F3) do M.small[k] = rects(rows, 1) end
M.digit3 = {}
for d = 0, 9 do M.digit3[d] = M.small[tostring(d)] end

-- countdown digits: the 3x5 font drawn x4 (12x20)
M.big = {}
for d = 1, 3 do M.big[d] = rects(F3[tostring(d)], 4) end

function M.glyph(r, x, y, flags)
  for i = 1, #r, 4 do
    lcd.drawFilledRectangle(x + r[i], y + r[i + 1], r[i + 2], r[i + 3], flags or FORCE)
  end
end

-- quad sprite: disc r=4 with the X erased (sprite #1); crash: ring with a black X
local DISC = { -4, -1, 9, 3, -3, -3, 7, 2, -3, 2, 7, 2, -1, -4, 3, 1, -1, 4, 3, 1 }
function M.quad(x, y, crash)
  local f = crash and ERASE or FORCE
  for i = 1, #DISC, 4 do
    lcd.drawFilledRectangle(x + DISC[i], y + DISC[i + 1], DISC[i + 2], DISC[i + 3], f)
  end
  if not crash then
    lcd.drawLine(x - 3, y - 3, x + 3, y + 3, SOLID, ERASE)
    lcd.drawLine(x - 3, y + 3, x + 3, y - 3, SOLID, ERASE)
    lcd.drawPoint(x, y, FORCE)
    return
  end
  lcd.drawLine(x + 4, y - 1, x + 4, y + 1, SOLID, FORCE)
  lcd.drawLine(x - 4, y - 1, x - 4, y + 1, SOLID, FORCE)
  lcd.drawLine(x - 1, y - 4, x + 1, y - 4, SOLID, FORCE)
  lcd.drawLine(x - 1, y + 4, x + 1, y + 4, SOLID, FORCE)
  lcd.drawLine(x + 4, y + 1, x + 1, y + 4, SOLID, FORCE)
  lcd.drawLine(x - 4, y + 1, x - 1, y + 4, SOLID, FORCE)
  lcd.drawLine(x + 4, y - 1, x + 1, y - 4, SOLID, FORCE)
  lcd.drawLine(x - 4, y - 1, x - 1, y - 4, SOLID, FORCE)
  lcd.drawPoint(x + 3, y + 3, FORCE)
  lcd.drawPoint(x - 3, y + 3, FORCE)
  lcd.drawPoint(x + 3, y - 3, FORCE)
  lcd.drawPoint(x - 3, y - 3, FORCE)
  lcd.drawLine(x - 2, y - 2, x + 2, y + 2, SOLID, FORCE)
  lcd.drawLine(x - 2, y + 2, x + 2, y - 2, SOLID, FORCE)
  lcd.drawPoint(x, y, ERASE)
end

-- selectable quads (sprite sheet #1 #2 #3 #4 #5 #10 #7 #9), same order as config.SKINS;
-- frame 2 spins the props: full 2x2 corner props become their outer diagonal
local SKINS = {
  { "...###...", "..#####..", ".#.###.#.", "###.#.###", "#########", "###.#.###", ".#.###.#.", "..#####..", "...###..." },
  { "#.......#", "..#####..", ".#.....#.", ".#.....#.", ".#..#..#.", ".#.....#.", ".#.....#.", "..#####..", "#.......#" },
  { "##.....##", "##.#.#.##", "..#...#..", "...###...", "#..###..#", "...###...", "..#...#..", "##.#.#.##", "##.....##" },
  { "##.....##", "##.###.##", "..#####..", ".#######.", ".#######.", ".#######.", "..#####..", "##.###.##", "##.....##" },
  { "#.......#", ".#.....#.", "..#...#..", "...###...", "....#....", "...###...", "..#...#..", ".#.....#.", "#.......#" },
  { "...###...", "...#.#...", "...###...", "###.#.###", "#.#####.#", "###.#.###", "...###...", "...#.#...", "...###..." },
  { "....#....", "...###...", "..#####..", ".###.###.", "###...###", ".###.###.", "..#####..", "...###...", "....#...." },
  { "##.....##", "###...###", ".###.###.", "..#####..", "...#.#...", "..#####..", ".###.###.", "###...###", "##.....##" },
}
-- the disc spins its erased X into a +
local DISC2 = { "...#.#...", "..##.##..", ".###.###.", "####.####", "#...#...#", "####.####", ".###.###.", "..##.##..", "...#.#..." }

local function spin(rows)
  local out = {}
  for y = 1, 9 do
    local r = ""
    for x = 1, 9 do
      local c = string.sub(rows[y], x, x)
      local cx, cy = x <= 2 and 1 or (x >= 8 and 9 or 0), y <= 2 and 1 or (y >= 8 and 9 or 0)
      if cx > 0 and cy > 0 then
        local full = true
        for yy = math.min(cy, cy == 1 and 2 or 8), math.max(cy, cy == 1 and 2 or 8) do -- int
          for xx = math.min(cx, cx == 1 and 2 or 8), math.max(cx, cx == 1 and 2 or 8) do -- int
            if string.sub(rows[yy], xx, xx) ~= "#" then full = false end
          end
        end
        if full and (x == cx) ~= (y == cy) then c = "." end
      end
      r = r .. c
    end
    out[y] = r
  end
  return out
end

-- rect lists exist only for the two skins in use (memory); call prepare() when a run starts
M.skins = {}
M.SKIN_COUNT = #SKINS
function M.prepare(a, b)
  for k in pairs(M.skins) do
    if k ~= a and k ~= b then M.skins[k] = nil end
  end
  for _, n in ipairs({ a, b }) do
    if not M.skins[n] then M.skins[n] = { rects(SKINS[n], 1), rects(n == 1 and DISC2 or spin(SKINS[n]), 1) } end -- int
  end
end

-- skin n at (x, y), frame 1 or 2: clear the disc under it, then the sprite
function M.skin(n, x, y, frame)
  if n == 1 and frame == 1 then return M.quad(x, y) end -- int
  for i = 1, #DISC, 4 do
    lcd.drawFilledRectangle(x + DISC[i], y + DISC[i + 1], DISC[i + 2], DISC[i + 3], ERASE)
  end
  if not M.skins[n] then M.prepare(n, n) end
  M.glyph(M.skins[n][frame], x - 4, y - 4)
end

-- line pattern by tail age: solid, 50 %, 25 %, 12 %
M.PAT = { [0] = SOLID, 0x55, 0x11, 0x01 }

-- drawLine that never sends an off-screen or negative endpoint (the firmware drops those lines)
function M.line(x1, y1, x2, y2, pat)
  if x1 < 0 or y1 < 0 or x2 < 0 or y2 < 0 or x1 >= LCD_W or x2 >= LCD_W or y1 >= LCD_H or y2 >= LCD_H then
    return false
  end
  lcd.drawLine(x1, y1, x2, y2, pat, FORCE)
  return true
end

return M
