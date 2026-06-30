-- dist/tests/hd_calib.lua  -- calibration demo for the HD term shim.
-- Run in-game:  wget run http://127.0.0.1:8080/fs/tests/hd_calib.lua
-- Prints the font metrics we need to pick a cell size, and draws a mock OS
-- screen (titlebar + body + statusbar) by emulating character cells, so we can
-- judge legibility before building the real shim.
local gpu = dofile("/os/gpu.lua")
local hdt = dofile("/os/hdterm.lua")
if not gpu.attach() then print("no tm_gpu"); return end

local W, H = gpu.size()
print("screen: " .. W .. "x" .. H)

-- font metrics: char width at each size (height we judge visually)
for s = 1, 3 do
  print("size " .. s .. ": charW ~= " .. (gpu.textLen("MMMMMMMMMM", s) / 10))
end

-- ---- mock OS screen, cells emulated at a chosen size ----------------------
local SIZE = 2
local cw = math.max(1, math.floor(gpu.textLen("M", SIZE)))
local ch = math.floor(cw * 1.7)
local cols, rows = hdt.cols(W, cw), hdt.rows(H, ch)
print("grid @ size " .. SIZE .. ": " .. cols .. "x" .. rows .. "  (cw=" .. cw .. " ch=" .. ch .. ")")

local white = gpu.fromCC(0x1)
local cyan  = gpu.fromCC(0x200)
local gray  = gpu.fromCC(0x80)
local black = gpu.fromCC(0x8000)

local function cell(col, row, s, fg, bg)
  local px, py = hdt.cellToPx(col, row, cw, ch)
  bg = bg or black
  gpu.fillRect(px, py, #s * cw, ch, bg)
  gpu.text(px, py, s, fg, bg, SIZE)
end

gpu.clear(black)
gpu.fillRect(0, 0, W, ch, cyan)                              -- titlebar
cell(2, 1, "PinguOS HD", black, cyan)
cell(cols - 6, 1, "12:40", black, cyan)
cell(2, 3, "Escritorio HD", white)
cell(2, 4, "Apps:  Claude   Fleet   Settings", white)
cell(2, 5, "Fleet: 3 turtles activas, 1 minando", white)
gpu.fillRect(0, (rows - 1) * ch, W, ch, gray)               -- statusbar
cell(2, rows, "OK  -  edicion HD", white, gray)
gpu.present()
print("drawn ok")
