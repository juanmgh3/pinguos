-- dist/os/gpu.lua  -- HD render layer over Tom's Peripherals `tm_gpu`.
--
-- Sibling to ui.lua: ui.lua draws to the character `term`; gpu.lua draws to the
-- HD pixel surface. Loads clean in plain Lua 5.4 (touches NO CC globals at load),
-- so its pure helpers (pack/fromCC/barFill) are unit-tested in dist/tests; the
-- tm_gpu I/O below is `luac -p`-checked and verified in-game.
--
-- See specs/pinguos/hd-command-center.md (Increment 1).
local gpu = {}

-- ---- pure helpers (unit-tested) --------------------------------------------

-- ARGB packing: a*2^24 + r*2^16 + g*2^8 + b, via arithmetic (no 5.4 bit-ops) so
-- it also runs on CC's Lua 5.1. tm_gpu accepts a single 0xAARRGGBB int.
function gpu.pack(r, g, b, a)
  a = a or 0xFF
  return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- CC's default 16-colour palette -> RGB, keyed by the colour VALUE
-- (colors.white = 0x1 ... colors.black = 0x8000) so tests pass plain numbers
-- without needing the `colors` global. Lets the HD layer honour PinguOS themes.
local CC_RGB = {
  [0x1]    = { 0xF0, 0xF0, 0xF0 }, -- white
  [0x2]    = { 0xF2, 0xB2, 0x33 }, -- orange
  [0x4]    = { 0xE5, 0x7F, 0xD8 }, -- magenta
  [0x8]    = { 0x99, 0xB2, 0xF2 }, -- lightBlue
  [0x10]   = { 0xDE, 0xDE, 0x6C }, -- yellow
  [0x20]   = { 0x7F, 0xCC, 0x19 }, -- lime
  [0x40]   = { 0xF2, 0xB2, 0xCC }, -- pink
  [0x80]   = { 0x4C, 0x4C, 0x4C }, -- gray
  [0x100]  = { 0x99, 0x99, 0x99 }, -- lightGray
  [0x200]  = { 0x4C, 0x99, 0xB2 }, -- cyan
  [0x400]  = { 0xB2, 0x66, 0xE5 }, -- purple
  [0x800]  = { 0x33, 0x66, 0xCC }, -- blue
  [0x1000] = { 0x7F, 0x66, 0x4C }, -- brown
  [0x2000] = { 0x57, 0xA6, 0x4E }, -- green
  [0x4000] = { 0xCC, 0x4C, 0x4C }, -- red
  [0x8000] = { 0x11, 0x11, 0x11 }, -- black
}

-- Resolve a CC palette colour to an opaque ARGB int (unknown -> white).
function gpu.fromCC(cc)
  local rgb = CC_RGB[cc] or CC_RGB[0x1]
  return gpu.pack(rgb[1], rgb[2], rgb[3])
end

-- Filled pixel width of a w-wide bar at fraction pct, clamped to [0,1], floored.
function gpu.barFill(w, pct)
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  return math.floor(w * pct)
end

-- ---- tm_gpu I/O (verified in-game; not unit-tested locally) ----------------

local dev    -- the wrapped tm_gpu peripheral, set by attach()
local W, H   -- pixel dimensions of the connected screen grid

-- Find and initialise the GPU. Returns true if an HD surface is present, so the
-- kernel can pick HD mode vs the terminal fallback.
function gpu.attach()
  dev = peripheral.find("tm_gpu")
  if not dev then return false end
  -- refreshSize() scans the monitor wall on a LATER server tick (it is async), so
  -- getSize() reads a stale 0x0 if polled in the same tick. Wait for it to resolve.
  dev.refreshSize()
  for _ = 1, 20 do
    W, H = dev.getSize()            -- getSize -> wpx, hpx, blocksX, blocksY, mult
    if W and W > 0 and H and H > 0 then break end
    os.sleep(0.1)
  end
  if not (W and W > 0) then W, H = 0, 0; return false end  -- no wall connected
  pcall(dev.setSize, 64)            -- max per-block resolution now that it is wired
  W, H = dev.getSize()              -- re-read after the resize
  return true
end

function gpu.attached() return dev ~= nil end
function gpu.size() return W, H end
function gpu.present() if dev then dev.sync() end end  -- push buffer to screens

function gpu.clear(color)
  if dev then dev.fill(color or gpu.fromCC(0x8000)) end
end
function gpu.fillRect(x, y, w, h, color)
  if dev then dev.filledRectangle(x, y, w, h, color) end
end
function gpu.rect(x, y, w, h, color)
  if dev then dev.rectangle(x, y, w, h, color) end
end
function gpu.line(x1, y1, x2, y2, color, smooth)
  if not dev then return end
  if smooth then dev.lineS(x1, y1, x2, y2, color) else dev.line(x1, y1, x2, y2, color) end
end
function gpu.text(x, y, s, fg, bg, size)
  if dev then dev.drawText(x, y, s, fg, bg, size) end
end
function gpu.image(x, y, ref)
  if dev then dev.drawImage(x, y, ref) end
end

-- A composed progress/fuel bar: background track + filled portion.
function gpu.bar(x, y, w, h, pct, fg, bg)
  if not dev then return end
  dev.filledRectangle(x, y, w, h, bg)
  local fw = gpu.barFill(w, pct)
  if fw > 0 then dev.filledRectangle(x, y, fw, h, fg) end
end

return gpu
