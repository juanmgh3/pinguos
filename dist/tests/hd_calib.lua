-- dist/tests/hd_calib.lua  -- standalone HD calibration A/B demo (no /os/ deps).
-- Run in-game:  wget run http://127.0.0.1:8080/fs/tests/hd_calib.lua
-- Draws the same mock OS panel at font size 1 (top) and size 2 (bottom) so we can
-- pick the cell/font size by eye. Talks to tm_gpu directly. Prints "calib v2".
local dev = peripheral.find("tm_gpu")
if not dev then print("no tm_gpu found"); return end

dev.refreshSize()
local W, H = 0, 0
for _ = 1, 20 do W, H = dev.getSize(); if W and W > 0 then break end; os.sleep(0.1) end
if not (W and W > 0) then print("0x0 - wall not connected"); return end
pcall(dev.setSize, 64)
W, H = dev.getSize()
print("calib v2  screen " .. W .. "x" .. H)

local function argb(r, g, b) return 0xFF * 0x1000000 + r * 0x10000 + g * 0x100 + b end
local white, cyan, gray, black, green =
  argb(240, 240, 240), argb(76, 153, 178), argb(76, 76, 76), argb(17, 17, 17), argb(87, 166, 78)

-- draw a mock OS panel filling [y0, y0+hh) using the given font size
local function panel(y0, hh, size, tag)
  local cw = math.max(1, math.floor(dev.getTextLength("M", size)))
  local ch = math.floor(cw * 1.7)
  local cols = math.floor(W / cw)
  local function txt(col, row, s, fg, bg)
    local x, y = (col - 1) * cw, y0 + (row - 1) * ch
    local w = math.min(#s * cw, W - x)          -- clamp to the right edge
    dev.filledRectangle(x, y, w, ch, bg or black)
    dev.drawText(x, y, s, fg, bg or black, size)
  end
  dev.filledRectangle(0, y0, W, ch, cyan)                    -- titlebar
  txt(1, 1, "PinguOS HD  [" .. tag .. "]  " .. cols .. "col", black, cyan)
  txt(1, 3, "Fleet: 3 turtles activas", white)
  txt(1, 4, "Claude  Settings  Update", white)
  local by = y0 + hh - ch - 2                                -- progress bar
  dev.filledRectangle(4, by, W - 8, ch, gray)
  dev.filledRectangle(4, by, math.floor((W - 8) * 0.66), ch, green)
end

dev.fill(black)
local half = math.floor(H / 2)
panel(0, half, 1, "size1")
dev.filledRectangle(0, half - 1, W, 2, white)               -- divider
panel(half, H - half, 2, "size2")
dev.sync()
print("drawn ok - compara arriba (size1) vs abajo (size2)")
