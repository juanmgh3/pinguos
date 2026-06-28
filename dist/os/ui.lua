-- dist/os/ui.lua
local text = require("text")
local ui = {}

ui.theme = {
  bg = colors.black, fg = colors.white,
  bar = colors.gray, barFg = colors.white,
  accent = colors.cyan, error = colors.red,
}

local function safe(c) -- degrade gracefully on non-advanced computers
  if term.isColour() then return c end
  if c == colors.black then return colors.black end
  if c == colors.gray or c == colors.lightGray then return colors.lightGray end
  return colors.white
end

function ui.setTheme(t) for k, v in pairs(t) do ui.theme[k] = v end end

function ui.clear(bg)
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
  ui.text(x, y, s, ui.theme.barFg, ui.theme.accent)
  return { x = x, y = y, w = #s, h = 1 }
end

function ui.hit(r, mx, my)
  return r ~= nil and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function ui.titleBar(title)
  local w = term.getSize()
  ui.fill(1, 1, w, 1, ui.theme.bar)
  ui.text(2, 1, title, ui.theme.barFg, ui.theme.bar)
  local close = " x "
  ui.text(w - #close + 1, 1, close, ui.theme.barFg, ui.theme.error)
  return { x = w - #close + 1, y = 1, w = #close, h = 1 }
end

function ui.wrap(s, width)
  return text.wrap(s, width or (select(1, term.getSize())))
end

return ui
