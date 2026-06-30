-- dist/os/ui.lua
local text = require("text")
local ui = {}

-- Keyboard-focus registry (Phase 2). Rebuilt each frame by ui.clear; populated by
-- the focusable helpers below. The focus manager (kernel) reads these; nothing here
-- depends on CC keyboard APIs, so non-HD just leaves focusEnabled = false.
ui._focusables = {}
ui._focusIndex = 1
ui._closeRegion = nil
ui.focusEnabled = false

ui.theme = {
  bg = colors.black, fg = colors.white,
  bar = colors.gray, barFg = colors.white,
  accent = colors.cyan, error = colors.red,
  shadow = colors.gray, panel = colors.gray,
}

local function safe(c) -- degrade gracefully on non-advanced computers
  if term.isColour() then return c end
  if c == colors.black then return colors.black end
  if c == colors.gray or c == colors.lightGray then return colors.lightGray end
  return colors.white
end

function ui.setTheme(t) for k, v in pairs(t) do ui.theme[k] = v end end

function ui.clear(bg)
  ui._focusables = {}
  ui._closeRegion = nil
  term.setBackgroundColor(safe(bg or ui.theme.bg))
  term.setTextColor(safe(ui.theme.fg))
  term.clear(); term.setCursorPos(1, 1)
end

function ui.fill(x, y, w, h, bg)
  term.setBackgroundColor(safe(bg))
  local row = string.rep(" ", w)
  for i = 0, h - 1 do term.setCursorPos(x, y + i); term.write(row) end
end

function ui.text(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  if fg then term.setTextColor(safe(fg)) end
  if bg then term.setBackgroundColor(safe(bg)) end
  term.write(s)
end

function ui.center(y, s, fg, bg)
  local w = term.getSize()
  ui.text(math.max(1, math.floor((w - #s) / 2) + 1), y, s, fg, bg)
end

function ui.button(x, y, label)
  local s = " " .. label .. " "
  ui._focusables[#ui._focusables + 1] = { x = x, y = y, w = #s, h = 1 }
  local fg, bg = ui.theme.barFg, ui.theme.accent
  if ui.focusEnabled and #ui._focusables == ui._focusIndex then
    fg, bg = ui.theme.accent, ui.theme.barFg   -- inverse = focus highlight
  end
  ui.text(x, y, s, fg, bg)
  return { x = x, y = y, w = #s, h = 1 }
end

-- A labelled colour swatch (e.g. the Ajustes accent picker): w cells of `color`
-- with " label" over it. Registers as focusable; when focused, prefixes ">" and
-- writes the label in white so the colour stays visible.
function ui.swatch(x, y, w, label, color)
  ui._focusables[#ui._focusables + 1] = { x = x, y = y, w = w, h = 1 }
  local focused = ui.focusEnabled and (#ui._focusables == ui._focusIndex)
  ui.fill(x, y, w, 1, color)
  ui.text(x, y, (focused and ">" or " ") .. label,
          focused and colors.white or colors.black, color)
  return { x = x, y = y, w = w, h = 1 }
end

function ui.hit(r, mx, my)
  return r ~= nil and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function ui.titleBar(title)
  local w = term.getSize()
  ui.fill(1, 1, w, 1, ui.theme.bar)
  ui.fill(1, 1, 1, 1, ui.theme.accent) -- left accent block
  ui.text(3, 1, title, ui.theme.barFg, ui.theme.bar)
  local close = " x "
  ui.text(w - #close + 1, 1, close, ui.theme.barFg, ui.theme.error)
  ui._closeRegion = { x = w - #close + 1, y = 1, w = #close, h = 1 }
  return { x = w - #close + 1, y = 1, w = #close, h = 1 }
end

function ui.wrap(s, width)
  return text.wrap(s, width or (select(1, term.getSize())))
end

-- A subtle drop shadow (gray cells) offset to the bottom-right of a region.
function ui.shadow(x, y, w, h)
  term.setBackgroundColor(safe(ui.theme.shadow))
  for i = 1, h do term.setCursorPos(x + w, y + i); term.write(" ") end
  term.setCursorPos(x + 1, y + h); term.write(string.rep(" ", w))
end

-- A framed two-tone panel with optional accent title strip + shadow.
function ui.panel(x, y, w, h, title)
  ui.shadow(x, y, w, h)
  ui.fill(x, y, w, h, ui.theme.panel)               -- frame
  ui.fill(x + 1, y + 1, w - 2, h - 2, ui.theme.bg)  -- interior
  if title then
    ui.fill(x, y, w, 1, ui.theme.accent)
    ui.text(x + 1, y, title, ui.theme.bg, ui.theme.accent)
  end
end

-- Bottom status bar with a left accent block and hint text.
function ui.statusBar(s)
  local w, h = term.getSize()
  ui.fill(1, h, w, 1, ui.theme.bar)
  ui.fill(1, h, 1, 1, ui.theme.accent)
  ui.text(3, h, s, ui.theme.barFg, ui.theme.bar)
end

-- A shadowed app tile (9x3) with a centered glyph and a label below.
-- labelBg lets the label blend into a non-black desktop wallpaper.
function ui.iconTile(x, y, glyph, color, label, selected, labelBg)
  ui.shadow(x, y, 9, 3)
  ui.fill(x, y, 9, 3, color)
  if selected then ui.fill(x, y, 9, 1, ui.theme.accent) end
  ui.text(x + 4, y + 1, glyph, ui.theme.bg, color)
  ui.text(x, y + 4, label, ui.theme.fg, labelBg or ui.theme.bg)
end

-- Desktop wallpapers (desktop-only; apps keep their own background).
local WALLS = { negro = colors.black, azul = colors.blue, morado = colors.purple, stars = colors.black }
ui.wallpapers = { "negro", "azul", "morado", "stars" }

function ui.wallpaper(kind)
  local bg = WALLS[kind] or colors.black
  ui.clear(bg)
  if kind == "stars" then
    local w, h = term.getSize()
    local pts = { {3,4},{11,6},{19,3},{27,8},{35,5},{43,7},{9,11},{22,13},{31,15},{46,12},{5,17},{15,9} }
    for _, p in ipairs(pts) do
      if p[1] <= w and p[2] <= h then ui.text(p[1], p[2], ".", colors.lightGray, bg) end
    end
  end
  return bg
end

-- Brief boot splash: tiny penguin + wordmark + version.
function ui.splash(version)
  ui.clear(ui.theme.bg)
  local w, h = term.getSize()
  local cy = math.floor(h / 2)
  ui.center(cy - 2, "(o<", colors.white)
  ui.center(cy - 1, "/) )", colors.white)
  ui.center(cy, "PinguOS", ui.theme.accent)
  ui.fill(math.floor(w / 2) - 3, cy + 1, 8, 1, ui.theme.accent)
  ui.center(cy + 2, "v" .. tostring(version), ui.theme.barFg)
  sleep(1.0)
end

return ui
