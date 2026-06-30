-- dist/tests/hd_calib.lua  -- standalone HD calibration demo (no /os/ deps, so a
-- single `wget run http://127.0.0.1:8080/fs/tests/hd_calib.lua` works without Update).
-- Talks to tm_gpu directly: prints font metrics and draws a mock OS screen by
-- emulating character cells, so we can pick the cell/font size for the real shim.
local dev = peripheral.find("tm_gpu")
if not dev then print("no tm_gpu found"); return end

dev.refreshSize()                         -- async; wait for the wall scan
local W, H = 0, 0
for _ = 1, 20 do W, H = dev.getSize(); if W and W > 0 then break end; os.sleep(0.1) end
if not (W and W > 0) then print("0x0 - wall not connected"); return end
pcall(dev.setSize, 64)
W, H = dev.getSize()
print("screen: " .. W .. "x" .. H)

local function argb(r, g, b) return 0xFF * 0x1000000 + r * 0x10000 + g * 0x100 + b end
local white, cyan, gray, black = argb(0xF0, 0xF0, 0xF0), argb(0x4C, 0x99, 0xB2), argb(0x4C, 0x4C, 0x4C), argb(0x11, 0x11, 0x11)

for s = 1, 3 do print("size " .. s .. ": charW ~= " .. (dev.getTextLength("MMMMMMMMMM", s) / 10)) end

local SIZE = 2
local cw = math.max(1, math.floor(dev.getTextLength("M", SIZE)))
local ch = math.floor(cw * 1.7)
local cols, rows = math.floor(W / cw), math.floor(H / ch)
print("grid @ size " .. SIZE .. ": " .. cols .. "x" .. rows .. "  (cw=" .. cw .. " ch=" .. ch .. ")")

local function cell(col, row, s, fg, bg)
  local x, y = (col - 1) * cw, (row - 1) * ch
  bg = bg or black
  dev.filledRectangle(x, y, #s * cw, ch, bg)
  dev.drawText(x, y, s, fg, bg, SIZE)
end

dev.fill(black)
dev.filledRectangle(0, 0, W, ch, cyan)                      -- titlebar
cell(2, 1, "PinguOS HD", black, cyan)
cell(cols - 6, 1, "12:40", black, cyan)
cell(2, 3, "Escritorio HD", white)
cell(2, 4, "Apps:  Claude   Fleet   Settings", white)
cell(2, 5, "Fleet: 3 turtles activas, 1 minando", white)
dev.filledRectangle(0, (rows - 1) * ch, W, ch, gray)        -- statusbar
cell(2, rows, "OK  -  edicion HD", white, gray)
dev.sync()
print("drawn ok")
