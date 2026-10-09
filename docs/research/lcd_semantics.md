# EdgeTX 2.11 stdlcd (128x64 B&W, PCB X7 / TX12) - Lua lcd.* ground truth

Sources (branch 2.11): `radio/src/gui/128x64/lcd.cpp`, `lcd.h`, `radio/src/lua/api_stdlcd_BW.cpp`,
`api_general.cpp` (constants), `radio/src/keys.h`, `radio/util/hw_defs/lua_keys.jinja`,
`radio/src/targets/taranis/{hal.h,board.h}`, `tools/encode-font.py`, `radio/src/gui/common/stdlcd/fonts.{h,cpp}`.

`coord_t` is `typedef int coord_t;` (signed 32-bit). `pixel_t` = uint8_t. `LcdFlags` = uint32_t.
`LCD_W=128, LCD_H=64, LCD_DEPTH=1`. Frame buffer `displayBuf[128*8]`, byte index `(y/8)*128 + x`, bit `y%8`
(bit0 = top row of the 8-row page). Bit 1 = pixel ON = DARK (see `pixel_polarity.md`).

## 1. Constants (as exported to Lua on B&W; `api_general.cpp` + `lcd.h`)

| Lua name | value | note |
|---|---|---|
| BLINK | 0x01 | |
| INVERS | 0x02 | **same bit as FORCE** |
| FORCE | 0x02 | point/line/rect flag |
| ERASE | 0x04 | **same bit as RIGHT** |
| RIGHT | 0x04 | text align right |
| ROUND | 0x08 | same bit as CONDENSED |
| LEFT | 0x00 | |
| CENTER | 0x20 (CENTERED) | same bit as PREC1 |
| BOLD | 0x40 | |
| PREC1 / PREC2 | 0x20 / 0x30 | drawNumber |
| SMLSIZE | 0x0200 | FONTSIZE_MASK = 0x0700 |
| MIDSIZE | 0x0300 | |
| DBLSIZE | 0x0400 | |
| XXLSIZE | 0x0500 | digits only font |
| TIMEHOUR | 0x2000 | |
| SOLID | 0xff | |
| DOTTED | 0x55 | |
| PLAY_NOW | 0x10 | `edgetx.h`: `#define PLAY_NOW 0x10`, `PLAY_BACKGROUND 0x20` |
| LCD_W / LCD_H | 128 / 64 | |

Lua exports: `#if LCD_W <= 212: FORCE, ERASE, ROUND`; always `SOLID, DOTTED, LCD_W, LCD_H, PLAY_NOW, PLAY_BACKGROUND, TIMEHOUR`.

### Events, BW (`keys.h`)
```
EVT_REFRESH=0x1000 EVT_ENTRY=0x1001 EVT_ENTRY_UP=0x1002 EVT_ROTARY_LEFT=0x1003 EVT_ROTARY_RIGHT=0x1004
_MSK_KEY_BREAK=0x20 _MSK_KEY_REPT=0x40 _MSK_KEY_FIRST=0x60 _MSK_KEY_LONG=0x80   (non-COLORLCD)
EVT_KEY_FIRST(k)=k|0x60  EVT_KEY_REPT(k)=k|0x40  EVT_KEY_LONG(k)=k|0x80  EVT_KEY_BREAK(k)=k|0x20
enum EnumKeys { KEY_MENU=0,KEY_EXIT=1,KEY_ENTER=2,KEY_PAGEUP=3,KEY_PAGEDN=4,KEY_UP=5,KEY_DOWN=6,
  KEY_LEFT=7,KEY_RIGHT=8,KEY_PLUS=9,KEY_MINUS=10,KEY_MODEL=11,KEY_TELE=12,KEY_SYS=13,KEY_SHIFT=14,KEY_BIND=15 }
```
Lua event names are generated per radio from `lua_keys.jinja`. **TX12 (mk1)**: hal.h defines keys PAGEUP, PAGEDN, EXIT,
ENTER, SYS, MDL (KEY_MODEL), TELE only (no UP/DOWN/LEFT/RIGHT/PLUS/MINUS/MENU/SHIFT) and no rotary encoder, so the
template's final `else` branches apply (derived by hand from the template and key enum; not executed):

| Lua constant | TX12 value |
|---|---|
| EVT_VIRTUAL_ENTER = BREAK(ENTER) | 0x22 |
| EVT_VIRTUAL_ENTER_LONG = LONG(ENTER) | 0x82 |
| EVT_VIRTUAL_EXIT = EVT_EXIT_BREAK = BREAK(EXIT) | 0x21 |
| EVT_VIRTUAL_PREV / DEC = EVT_ROTARY_LEFT | 0x1003 |
| EVT_VIRTUAL_NEXT / INC = EVT_ROTARY_RIGHT | 0x1004 |
| EVT_VIRTUAL_PREV_PAGE = BREAK(PAGEUP) | 0x23 |
| EVT_VIRTUAL_NEXT_PAGE = BREAK(PAGEDN) | 0x24 |
| EVT_VIRTUAL_MENU = BREAK(MODEL) | 0x2B |
| EVT_VIRTUAL_MENU_LONG = LONG(MODEL) | 0x8B |
| EVT_ENTER_FIRST/BREAK/LONG/REPT (also EVT_ROT_*) | 0x62 / 0x22 / 0x82 / 0x42 |
| EVT_PAGEUP_FIRST/BREAK/LONG/REPT | 0x63 / 0x23 / 0x83 / 0x43 |
| EVT_PAGEDN_FIRST/BREAK/LONG/REPT | 0x64 / 0x24 / 0x84 / 0x44 |
| EVT_MODEL_FIRST/BREAK/LONG/REPT | 0x6B / 0x2B / 0x8B / 0x4B |
| EVT_TELEM_FIRST/BREAK/LONG/REPT | 0x6C / 0x2C / 0x8C / 0x4C |
| EVT_SYS_FIRST/BREAK/LONG/REPT | 0x6D / 0x2D / 0x8D / 0x4D |
| EVT_ROT_LEFT / EVT_ROT_RIGHT | 0x1003 / 0x1004 |

Not defined on TX12: EVT_UP/DOWN/LEFT/RIGHT/PLUS/MINUS/MENU/SHIFT_*, EVT_EXIT_FIRST/LONG/REPT (only EVT_EXIT_BREAK).
Other X7 radios with PLUS/MINUS differ (`EVT_VIRTUAL_PREV = EVT_KEY_FIRST(KEY_PLUS)` etc.).

## 2. Pixel primitive

```cpp
void lcdMaskPoint(uint8_t * p, uint8_t mask, LcdFlags att)
{
  ASSERT_IN_DISPLAY(p);
  if (att & FORCE)      *p |= mask;     // set pixel (dark)
  else if (att & ERASE) *p &= ~mask;    // clear pixel (light)
  else                  *p ^= mask;     // DEFAULT = XOR (toggle)
}
void lcdDrawPoint(coord_t x, coord_t y, LcdFlags att)
{
  uint8_t * p = &displayBuf[ y / 8 * LCD_W + x ];
  if (IS_IN_DISPLAY(p)) {                // only a *buffer-range* check, NOT an x/y range check
    lcdMaskPoint(p, bfBit<uint8_t>(y % 8), att);
  }
}
```
* **Default (flags 0) = XOR**. FORCE (0x02) = set; ERASE (0x04) = clear; FORCE wins if both. INVERS == FORCE bit, so
  `INVERS` on drawPoint/drawLine/drawRectangle/drawFilledRectangle behaves as FORCE (set).
* Lua `lcd.drawPoint(x,y[,flags])` has no clipping (`lcdDrawPoint(x, y, att)` directly). Normal range x 0..127, y 0..63.
  x>=128 wraps into the next page's left side (x=128,y=0 -> page 1 col 0); x<0 wraps to the previous page; y>=64 ignored
  (index >= 1024); y<0 is undefined behaviour (negative shift). A mock should treat out-of-range as no-op (or replicate the wrap for x).
* `lcd.clear()` = `memset(displayBuf, 0, ...)` -> all pixels OFF (light).

## 3. Lines

Lua wrapper (`api_stdlcd_BW.cpp`):
```cpp
coord_t x1 = luaL_checkunsigned(L, 1); ... coord_t y2 = luaL_checkunsigned(L, 4);
uint8_t pat = luaL_checkunsigned(L, 5);        // REQUIRED (not optional!)
LcdFlags flags = luaL_checkunsigned(L, 6);     // REQUIRED (not optional!)
if (x1 > LCD_W || y1 > LCD_H || x2 > LCD_W || y2 > LCD_H) return 0;   // skip whole line
if (pat == SOLID) {
  if (x1 == x2) { lcdDrawSolidVerticalLine(x1, y1<y2 ? y1 : y2, y1<y2 ? (y2-y1)+1 : (y1-y2)+1, flags); return 0; }
  else if (y1 == y2) { lcdDrawSolidHorizontalLine(x1<x2 ? x1 : x2, y1, x1<x2 ? (x2-x1)+1 : (x1-x2)+1, flags); return 0; }
}
lcdDrawLine(x1, y1, x2, y2, pat, flags);
```
* Skip rule: **strictly greater** than LCD_W (128) / LCD_H (64) (so coordinate 128 or 64 itself is accepted, then clipped).
  Negative coordinates: `luaL_checkunsigned` wraps mod 2^32 and the value is stored into signed `int` coord_t, so -1 is
  -1 again: **negative coordinates are NOT skipped** by this test (my reading; docs claim off-screen => not drawn but only the `>` test exists). They get clipped by the line routines (axis-aligned) or hit lcdDrawPoint (diagonal).
* With fewer than 6 args (`lcd.drawLine(x1,y1,x2,y2)`) this source raises a Lua argument error (checkunsigned, not optunsigned). Scripts must pass `SOLID, 0` (or `SOLID, FORCE`).
* flags=0 XORs; on a cleared screen XOR == set.

Axis-aligned SOLID routines:
```cpp
void lcdDrawHorizontalLine(coord_t x, coord_t y, coord_t w, uint8_t pat, LcdFlags att)
{
  if (y < 0 || y >= LCD_H || w == 0) return;
  if (w < 0) { x = x + w + 1; w = -w; }
  if (x + w <= 0 || x >= LCD_W) return;
  if (x < 0) { w += x; x = 0; }
  if (x + w > LCD_W) { w = LCD_W - x; }
  uint8_t *p  = &displayBuf[ y / 8 * LCD_W + x ];
  uint8_t msk = bfBit<uint8_t>(y % 8);
  while (w--) {
    if(pat & 1) { lcdMaskPoint(p, msk, att); pat = (pat >> 1) | 0x80; }  // bit set: rotate a 1 in
    else        { pat = pat >> 1; }                                      // bit clear: shift a 0 in (pattern decays)
    p++;
  }
}
void lcdDrawVerticalLine(coord_t x, coord_t y, coord_t h, uint8_t pat, LcdFlags att)
{
  if (x < 0 || x >= LCD_W || h == 0) return;
  if (h < 0) { y = y + h + 1; h = -h; }
  if (y + h <= 0 || y >= LCD_H) return;
  if (y < 0) { h += y; y = 0; }
  if (y + h > LCD_H) { h = LCD_H - y; }
  if (pat==DOTTED && !(y%2)) pat = ~pat;
  ... byte-wise lcdMaskPoint(p, mask & pat, att)   // pat bit n applies to absolute row (page*8+n)
}
```
For SOLID (0xff) both are plain exactly-clipped runs (no wrap). Lua only reaches them with 0xff (axis-aligned + SOLID); any other pattern goes to lcdDrawLine.

General line (diagonals and every non-SOLID pattern):
```cpp
void lcdDrawLine(coord_t x1, coord_t y1, coord_t x2, coord_t y2, uint8_t pat, LcdFlags att)
{
  int dx = x2-x1, dy = y2-y1;
  int dxabs = abs(dx), dyabs = abs(dy);
  int sdx = sgn(dx), sdy = sgn(dy);
  int x = dyabs>>1, y = dxabs>>1;
  int px = x1, py = y1;
  if (dxabs >= dyabs) {                    // x-major
    for (int i=0; i<=dxabs; i++) {
      if ((1<<(px%8)) & pat) lcdDrawPoint(px, py, att);
      y += dyabs;
      if (y>=dxabs) { y -= dxabs; py += sdy; }
      px += sdx;
    }
  } else {                                 // y-major
    for (int i=0; i<=dyabs; i++) {
      if ((1<<(py%8)) & pat) lcdDrawPoint(px, py, att);
      x += dxabs;
      if (x >= dyabs) { x -= dyabs; px += sdx; }
      py += sdy;
    }
  }
}
```
* Both endpoints inclusive (dxabs+1 or dyabs+1 points), starting at (x1,y1) - direction matters for tie rounding.
* `pat` is NOT rotated per pixel: it is tested by the **absolute coordinate** along the major axis, bit `(px % 8)` (x-major) or `(py % 8)` (y-major). DOTTED (0x55) draws pixels where that coordinate is even. Horizontal DOTTED: even x; vertical DOTTED: even y; a 45 degree diagonal (dxabs>=dyabs) -> even x.
* Each plotted pixel goes through `lcdDrawPoint` with `att` (XOR by default; no x clipping -> x>=128 wraps, see section 2).

## 4. Rectangles

```cpp
void lcdDrawRect(coord_t x, coord_t y, coord_t w, coord_t h, uint8_t pat, LcdFlags att)
{
  lcdDrawVerticalLine(x, y, h, pat, att);
  lcdDrawVerticalLine(x+w-1, y, h, pat, att);
  if (~att & ROUND) { x+=1; w-=2; }
  lcdDrawHorizontalLine(x, y+h-1, w, pat, att);
  lcdDrawHorizontalLine(x, y, w, pat, att);
}
void lcdDrawFilledRect(coord_t x, coord_t y, coord_t w, coord_t h, uint8_t pat, LcdFlags att)
{
  for (coord_t i=y; i<y+h; i++) {
    if ((att&ROUND) && (i==y || i==y+h-1)) lcdDrawHorizontalLine(x+1, i, w-2, pat, att);
    else                                   lcdDrawHorizontalLine(x, i, w, pat, att);
    pat = (pat >> 1) + ((pat & 1) << 7);   // rotate pattern per row
  }
}
```
Lua: `lcd.drawRectangle(x,y,w,h[,flags])` -> `lcdDrawRect(x, y, w, h, 0xff, flags)`;
`lcd.drawFilledRectangle(x,y,w,h[,flags])` -> `lcdDrawFilledRect(x, y, w, h, SOLID, flags)`;
`lcd.drawGauge(x,y,w,h,num,den[,flags])` -> `lcdDrawRect(x,y,w,h,0xff,flags); len = limit(0, ((w-2)*num + den/2)/den, w-2); if (len>0) lcdDrawSolidFilledRect(x+1,y+1,len,h-2,flags);`
* Outline: left/right columns full height at x and x+w-1; top/bottom rows from x+1, length w-2. Corners drawn once (no XOR double toggle).
  w=2 -> horizontals length 0 -> nothing. w=1 -> quirk: w-2=-1 takes the negative-width branch and plots one pixel at x+1 on the top and bottom rows (outside the rect). h=1 -> top and bottom row are the same row: with XOR the middle pixels toggle twice (net unchanged), only the 2 end pixels remain.
* **Filled rect default (flags 0) = XOR/invert, NOT black fill.** `FORCE` = fill dark. `ERASE` = fill light. `INVERS` (0x02 == FORCE) = fill dark.
  Rows y..y+h-1, columns x..x+w-1, clipped to the screen; h<=0 draws nothing; w<0 is mirrored by the horizontal-line routine.
  Idioms: set `...,FORCE)`; clear `...,ERASE)`; invert region `...,0)`.

## 5. Text

Glyph tables (`font_5x7`, `font_4x6`, `font_8x10`, `font_10x14`) are column-major bytes, bit0 = top row; a column whose
bytes are all 0xff is a *skipped* column. Dimensions used by the firmware:
```cpp
static const uint8_t fontWidth[]  = { 5, 3, 5, 8, 10, 22, 5 };   // idx = FONTSIZE>>8: std, TIN, SML, MID, DBL, XXL, BOLD
static const uint8_t fontHeight[] = { 7, 5, 6, 12, 16, 38, 7 };
// charSize = (height+7)/8 * width bytes ; data = &font[(c - 0x20) * charSize]
```
Cell sizes: std 5 cols x 7 rows; SML 5 cols x 6 rows (+ descender row, below); MID 8 x 12; DBL 10 x 16 (art is 14 high).
(File names 4x6/8x10/10x14 are the art sizes; the cell is what the table says.) Bitmaps are in `font5x7.lua`, `font4x6.lua`,
`font8x10.lua`, `font10x14.lua`.

```cpp
getPatternWidth: counts columns where any byte != 0xff          // visible glyph width
getCharWidth(c, flags) = getPatternWidth(...)
getTextWidth:  width += getCharWidth(c, flags) + 1;             // advance = visible columns + 1
```
Std font widths: digits 4 (advance 5), most letters 5 (adv 6), `i l` 3 (adv 4), `I` 3, `.` `|` `!` 1 (adv 2), space 2 (adv 3), `-` 4.
SML: most letters/digits 4 (adv 5), `M W m w` 5, `I T Y i l j c v` 3. DBL: `A` 10 (adv 11), `3` 8 (adv 9), space 5 (adv 6).

Core glyph renderer (what draws every character):
```cpp
void lcdPutPattern(coord_t x, coord_t y, const uint8_t * pattern, uint8_t width, uint8_t height, LcdFlags flags)
{
  bool blink = false, inv = false;
  if (flags & BLINK) { if (BLINK_ON_PHASE) { if (flags & INVERS) inv = true; else blink = true; } }
  else if (flags & INVERS) inv = true;
  uint8_t lines = (height+7)/8;
  for (int8_t i=0; i<width+2; i++) {           // col 0 = leading pad, 1..width = glyph, width+1 = trailing pad
    if (x >= 0 && x < LCD_W) {
      uint8_t b[5] = { 0 };
      if (i==0) {
        if (x==0 || !inv) { lcdNextPos++; continue; }   // pad column only painted for INVERS (and x>0)
        else x--;                                       // INVERS: paint pad at x-1
      }
      else if (i<=width) {
        uint8_t skip = true;
        for (uint8_t j=0; j<lines; j++) { b[j] = *(pattern++); if (b[j] != 0xff) skip = false; }
        if (skip) { if (flags & FIXEDWIDTH) { /* b[]=0 */ } else continue; }  // skipped column: no draw, no advance
        if ((flags & CONDENSED) && i==2) continue;
      }
      for (int8_t j=-1; j<=height; j++) {
        bool plot;
        if (j < 0 || ((j == height) && !(FONTSIZE(flags) == SMLSIZE))) {   // row above / below the cell
          plot = false;
          if (height >= 12) continue;           // MIDSIZE / DBLSIZE / XXL: no extra rows
          if (j<0 && !inv) continue;            // row above only for INVERS
          if (y+j < 0) continue;
        } else {
          plot = b[j / 8] & (1 << (j % 8));
        }
        if (inv) plot = !plot;
        if (!blink) lcdDrawPoint(x, y+j, plot ? FORCE : ERASE);
      }
    }
    x++;                                        // (also after the INVERS x-- , restoring x)
    lcdNextPos++;
  }
}
```
Consequences:
1. **Text is opaque.** Every non-skipped glyph column writes its whole cell height: set pixels FORCE, unset pixels ERASE (never XOR). So text clears its background to light. User FORCE/ERASE flags are irrelevant (and ERASE bit == RIGHT => right-aligned text).
2. Text `y` = top row of the cell. std glyph rows y..y+6, SML y..y+5 (+ y+6 descender), MID y..y+11, DBL y..y+15. No vertical offset.
3. Non-INVERS std font (height 7 < 12, not SML): for each drawn column (incl. trailing pad column) row y+7 is **ERASEd** as well. The leading pad column and row y-1 are not touched without INVERS.
   SMLSIZE: row j=6 is read from glyph bit 6 (descender row: only `, ; Q g j p q y` have bit 6 set); no extra erase row below, so SML covers y..y+6.
   MID/DBL: only rows y..y+height-1.
4. **INVERS**: plot is flipped (glyph pixels erased, background FORCE-set, 1px dark border). Pad columns are painted: leading pad at x-1 (only if x>0) and trailing pad after glyph; extra rows y-1 and y+7 for std (box rows y-1..y+7), y-1..y+6 for SML, none for MID/DBL. Skipped (0xff) columns are not painted. Result: dark box with light glyphs, box width = advance+1 (from x-1 through the trailing pad).
   BLINK alone: during the blink-ON phase nothing is drawn (not even the erase), otherwise normal. BLINK|INVERS: inverted in ON phase, **normal** (not inverted) in OFF phase. A mock may treat BLINK as always-off (draw normally) or ignore it.
5. Advance: `lcdNextPos` starts at x-1, +1 per pad column, +1 per non-skipped glyph column => next char x = x + visibleCols + 1.
6. Clipping: per column `x>=0 && x<LCD_W`; per pixel `lcdDrawPoint` (y>=64 dropped; y+j<0 undefined for glyph rows).

```cpp
void lcdDrawSizedText(coord_t x, coord_t y, const char * s, uint8_t len, LcdFlags flags)
{
  const coord_t orig_x = x;
  uint8_t width = 0;
  if (flags & RIGHT)         { width = getTextWidth(s, len, flags); x -= width; }
  else if (flags & CENTERED) { width = getTextWidth(s, len, flags); x -= width / 2; }
  while (len--) {
    unsigned char c = *s;
    /* c >= 0x20: c = map_utf8_char(...); lcdDrawChar(x, y, c, flags); x = lcdNextPos;
       0x1E newline: len = orig_len; x = orig_x; y += FH(8) (+FH more for DBLSIZE, +4 MIDSIZE, -1 SMLSIZE)
       0x1D tab: x |= 0x3F; x += 1;   other <0x20: x += c*FW/2 */
    s++;
  }
  lcdLastRightPos = x;
  lcdNextPos = x;
  if (fontsize == MIDSIZE) lcdLastRightPos += 1;
  if (flags & RIGHT) { lcdLastRightPos -= width; lcdNextPos -= width; lcdLastLeftPos = lcdLastRightPos; lcdLastRightPos = orig_x; }
  else lcdLastLeftPos = orig_x;
}
```
* `lcd.drawText(x,y,s[,flags])` returns **nothing** (`return 0`). `lcd.getLastRightPos()` (= `lcd.getLastPos()`) returns
  `lcdLastRightPos`: for left-aligned text = x + sum(visibleCols+1) (+1 more for MIDSIZE), i.e. the x just after the last char's trailing pad;
  for RIGHT-aligned = the original x. `lcd.getLastLeftPos()` = start x (x-width for RIGHT). Updated by drawText / drawNumber (via lcdDrawText) / drawTimer, not by lines/rects.
* Text with CENTER: x -= width/2 (integer division), width = sum(visibleCols+1).
* `lcd.drawNumber(x,y,val,flags)` builds the string (PREC1 one decimal, PREC2 two), then `flags &= ~(LEADING0|PREC1|PREC2); lcdDrawText(x,y,str,flags)` - same fonts/advance.
* DBLSIZE font contains only: space, `, - . / 0-9 :` (codes 44..58), A-Z, a-z, `_`. Firmware remap: `','..':'` -> slot c-44+1; `/` and `_` both use slot 4 (underscore glyph); A-Z -> slot c-65+16; a-z -> c-97+42; every other char -> slot 0 = blank space glyph (so `! ( + =` etc. render as blank, advance 6). `font10x14.lua` has this mapping already resolved.
* std, SML and MID fonts cover ASCII 32..127.
* Line spacing constants: FH = 8, FW = 6, FWNUM = 5.

## 6. Bitmaps (lcd.drawPixmap) - reference only
`lcdDraw1bitBitmap` overwrites bytes (`*p = b`, with page shifting), not XOR; INVERS inverts the bitmap bytes.

## 7. Mock cheat-sheet

| call | flags=0 | FORCE | ERASE | INVERS |
|---|---|---|---|---|
| drawPoint | XOR | set | clear | = FORCE (set) |
| drawLine | XOR per pixel | set | clear | set |
| drawRectangle | XOR outline (corners once) | set | clear | set |
| drawFilledRectangle | XOR (inverts) | fill dark | fill light | fill dark |
| drawText/Number | opaque: glyph ON, cell bg OFF | = INVERS | = RIGHT align | inverted box |

All lcd.* drawing functions are no-ops unless `luaLcdAllowed` (only when called from a script's run/draw context). A mock can ignore this.
