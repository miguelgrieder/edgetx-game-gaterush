std = "lua52"
max_line_length = false
-- EdgeTX B&W API (read-only)
read_globals = {
  "lcd", "model", "getValue", "getTime", "playTone", "playHaptic", "playFile", "getUsage",
  "killEvents", "getStickMode", "getFieldInfo",
  "LCD_W", "LCD_H", "SOLID", "DOTTED", "FORCE", "ERASE", "ROUND", "BLINK", "INVERS",
  "SMLSIZE", "MIDSIZE", "DBLSIZE", "CENTER", "RIGHT", "PLAY_NOW", "PLAY_BACKGROUND",
  "EVT_VIRTUAL_ENTER", "EVT_VIRTUAL_ENTER_LONG", "EVT_VIRTUAL_EXIT", "EVT_VIRTUAL_NEXT",
  "EVT_VIRTUAL_PREV", "EVT_VIRTUAL_INC", "EVT_VIRTUAL_DEC", "EVT_VIRTUAL_INC_REPT",
  "EVT_VIRTUAL_DEC_REPT", "EVT_ENTER_BREAK", "EVT_ENTER_LONG", "EVT_EXIT_BREAK",
  "EVT_ROT_RIGHT", "EVT_ROT_LEFT", "EVT_ROT_BREAK", "EVT_ROT_LONG",
}
files["tools"] = { globals = { "lcd", "io", "model" } , std = "+lua52" }
files["tests"] = { std = "+lua52" }
