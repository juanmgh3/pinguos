-- dist/os/hdterm.lua  -- an HD "terminal": a CC `term` redirect rendered on Tom's
-- pixel surface via gpu.lua, so the kernel desktop and every app render in HD with
-- no app changes (term.redirect onto this). Adapted from Tom's official term_emu.lua
-- (two-buffer diffing, per-cell draw). See specs/pinguos/toms-peripherals-reference.md.
--
-- Pure grid math (cols/cellToPx/pxToCell) is unit-tested; the redirect drives gpu.*
-- (verified in-game). Loads clean in plain Lua (touches no CC globals at top level).
local hdterm = {}

-- ---- pure cell <-> pixel grid math (unit-tested) --------------------------
function hdterm.cols(wpx, cw) return math.floor(wpx / cw) end
function hdterm.rows(hpx, ch) return math.floor(hpx / ch) end
function hdterm.cellToPx(col, row, cw, ch)
  return 1 + (col - 1) * cw, 1 + (row - 1) * ch          -- 1-based pixels (tm_gpu origin)
end
function hdterm.pxToCell(px, py, cw, ch)
  return math.floor((px - 1) / cw) + 1, math.floor((py - 1) / ch) + 1
end

-- CC's 16-colour palette -> ARGB, keyed by colour NAME (no `colors` global at load)
local NAME_ARGB = {
  white = 0xFFF0F0F0, orange = 0xFFF2B233, magenta = 0xFFE57FD8, lightBlue = 0xFF99B2F2,
  yellow = 0xFFDEDE6C, lime = 0xFF7FCC19, pink = 0xFFF2B2CC, gray = 0xFF4C4C4C,
  lightGray = 0xFF999999, cyan = 0xFF4C99B2, purple = 0xFFB266E5, blue = 0xFF3366CC,
  brown = 0xFF7F664C, green = 0xFF57A64E, red = 0xFFCC4C4C, black = 0xFF111111,
}

-- ---- the term redirect (I/O via gpu.lua; verified in-game) -----------------
-- new(gpu, opts) -> { term, flush, sync, mapPixel, setAuto }
--   gpu  : the gpu.lua module (already gpu.attach()'d)
--   opts : { scale = 2 } font size multiplier
function hdterm.new(gpu, opts)
  opts = opts or {}
  local scale = opts.scale or 2
  local charW, charH = scale * 6, scale * 9
  local wpx, hpx = gpu.size()
  local W = hdterm.cols(wpx, charW)
  local H = hdterm.rows(hpx, charH)

  -- palette keyed by CC colour VALUE (colors.white=1 ... black=0x8000)
  local palette = {}
  for name, argb in pairs(NAME_ARGB) do
    if colors[name] then palette[colors[name]] = argb end
  end
  local function argbOf(c) return palette[c] or 0xFF111111 end

  local cur_x, cur_y = 1, 1
  local fg, bg = colors.white, colors.black
  local blink = false
  local buf, prev = {}, {}              -- buf = pending, prev = on-screen
  for y = 1, H do
    buf[y], prev[y] = {}, {}
    for x = 1, W do
      buf[y][x]  = { ch = " ", fg = fg, bg = bg }
      prev[y][x] = { ch = "\0", fg = -1, bg = -1 }   -- force first full draw
    end
  end

  -- paint one cell to the GPU buffer (no present)
  local function paint(x, y, cell)
    local px, py = hdterm.cellToPx(x, y, charW, charH)
    gpu.fillRect(px, py, charW, charH, argbOf(cell.bg))
    if cell.ch ~= " " then
      local s = gpu.textLen(cell.ch, scale)
      gpu.text(px + math.floor((charW - s) / 2), py, cell.ch, argbOf(cell.fg), -1, scale)
    end
  end

  local auto = false                    -- when true, paint on every write
  local function set(x, y, ch, f, b)
    if x < 1 or x > W or y < 1 or y > H then return end
    buf[y][x] = { ch = ch, fg = f, bg = b }
    if auto then paint(x, y, buf[y][x]) end
  end

  local r = {}                          -- the redirect object

  function r.write(s)
    s = tostring(s)
    for i = 1, #s do
      local x = cur_x + i - 1
      if x >= 1 and x <= W and cur_y >= 1 and cur_y <= H then
        set(x, cur_y, s:sub(i, i), fg, bg)
      end
    end
    cur_x = cur_x + #s
  end

  -- blit: per-char fg/bg from hex strings (CC colour value = 2^digit)
  function r.blit(text, tfg, tbg)
    for i = 1, #text do
      local x = cur_x + i - 1
      if x >= 1 and x <= W and cur_y >= 1 and cur_y <= H then
        local f = 2 ^ (tonumber(tfg:sub(i, i), 16) or 0)
        local b = 2 ^ (tonumber(tbg:sub(i, i), 16) or 15)
        set(x, cur_y, text:sub(i, i), f, b)
      end
    end
    cur_x = cur_x + #text
  end

  function r.clear()
    for y = 1, H do for x = 1, W do set(x, y, " ", fg, bg) end end
  end
  function r.clearLine()
    for x = 1, W do set(x, cur_y, " ", fg, bg) end
  end
  function r.scroll(n)
    local nb = {}
    for y = 1, H do
      nb[y] = {}
      for x = 1, W do
        local src = buf[y + n]
        nb[y][x] = (src and src[x]) or { ch = " ", fg = fg, bg = bg }
      end
    end
    buf = nb
    if auto then for y = 1, H do for x = 1, W do paint(x, y, buf[y][x]) end end end
  end

  function r.setCursorPos(x, y) cur_x, cur_y = math.floor(x), math.floor(y) end
  function r.getCursorPos() return cur_x, cur_y end
  function r.getSize() return W, H end
  function r.setTextColor(c) fg = c end
  function r.setBackgroundColor(c) bg = c end
  function r.getTextColor() return fg end
  function r.getBackgroundColor() return bg end
  function r.isColor() return true end
  function r.setCursorBlink(b) blink = b end
  function r.getCursorBlink() return blink end
  function r.getPaletteColor(c)
    local a = argbOf(c)                                   -- arithmetic (no 5.3 bit-ops; CC is 5.1)
    return (math.floor(a / 0x10000) % 0x100) / 255,
           (math.floor(a / 0x100) % 0x100) / 255,
           (a % 0x100) / 255
  end
  function r.setPaletteColor() end                        -- theme palette is fixed; stub
  -- British spellings CC also exposes
  r.setPaletteColour = r.setPaletteColor
  r.setTextColour = r.setTextColor
  r.setBackgroundColour = r.setBackgroundColor
  r.getTextColour = r.getTextColor
  r.getBackgroundColour = r.getBackgroundColor
  r.isColour = r.isColor
  r.getPaletteColour = r.getPaletteColor

  -- flush: draw only changed cells, then present once (the coalesced redraw)
  local function flush()
    for y = 1, H do
      for x = 1, W do
        local c, p = buf[y][x], prev[y][x]
        if c.ch ~= p.ch or c.fg ~= p.fg or c.bg ~= p.bg then
          paint(x, y, c)
          p.ch, p.fg, p.bg = c.ch, c.fg, c.bg
        end
      end
    end
    gpu.present()
  end

  return {
    term = r,
    flush = flush,
    sync = flush,
    mapPixel = function(px, py) return hdterm.pxToCell(px, py, charW, charH) end,
    setAuto = function(v) auto = v end,
    size = function() return W, H end,
  }
end

return hdterm
