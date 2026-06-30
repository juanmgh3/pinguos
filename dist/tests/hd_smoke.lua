-- dist/tests/hd_smoke.lua  -- in-game smoke test for the gpu.lua HD layer.
-- Run in-game (no pasting needed):
--   wget run http://127.0.0.1:8080/fs/tests/hd_smoke.lua
-- Draws relative to the real screen size so it fits any resolution, and prints
-- the measured size. Not part of the installed OS (the manifest skips tests/).
local gpu = dofile("/os/gpu.lua")
if not gpu.attach() then print("No tm_gpu found"); return end

local W, H = gpu.size()
print("HD size: " .. W .. "x" .. H)

gpu.clear(gpu.fromCC(0x8000))                                  -- black background

local pad  = 2
local boxW = math.floor(W * 0.5)
local boxH = math.floor(H * 0.3)
gpu.fillRect(pad, pad, boxW, boxH, gpu.fromCC(0x200))          -- cyan box

gpu.text(pad, math.floor(H * 0.45), "PinguOS HD", gpu.fromCC(0x1))  -- white label

local barH = math.max(3, math.floor(H * 0.08))
local barY = H - barH - pad
gpu.bar(pad, barY, W - 2 * pad, barH, 0.66, gpu.fromCC(0x2000), gpu.fromCC(0x80)) -- green 66%

gpu.present()
print("drawn ok")
