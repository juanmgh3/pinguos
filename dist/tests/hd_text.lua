-- dist/tests/hd_text.lua  -- standalone text legibility test (no /os/ deps).
-- Run in-game:  wget run http://127.0.0.1:8080/fs/tests/hd_text.lua
-- Just text on a clean dark background, at sizes 1/2/3 and two draw methods, so we
-- can pick a size and the right drawText call. tm_gpu is 1-based. Prints "text v1".
local dev = peripheral.find("tm_gpu")
if not dev then print("no tm_gpu found"); return end

dev.refreshSize()
local W, H = 0, 0
for _ = 1, 20 do W, H = dev.getSize(); if W and W > 0 then break end; os.sleep(0.1) end
if not (W and W > 0) then print("0x0 - wall not connected"); return end
pcall(dev.setSize, 64)
W, H = dev.getSize()
print("text v1  screen " .. W .. "x" .. H)

local function argb(r, g, b) return 0xFF * 0x1000000 + r * 0x10000 + g * 0x100 + b end
local white, cyan, black = argb(240, 240, 240), argb(76, 153, 178), argb(17, 17, 17)

dev.fill(black)
dev.drawText(4, 4,  "Size1  PinguOS HD  (4 args)", white)          -- 4 args, no bg
dev.drawText(4, 22, "Size2  PinguOS HD", white, black, 2)          -- 6 args, bg+size
dev.drawText(4, 56, "Size3  PinguOS", white, black, 3)             -- 6 args, bg+size
dev.filledRectangle(1, 110, W, 30, cyan)                            -- a titlebar
dev.drawText(6, 116, "Size2 negro sobre cian", black, cyan, 2)     -- text on colour
dev.sync()
print("drawn ok - cual size se lee mejor? la barra cian se ve bien?")
