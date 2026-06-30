-- dist/tests/hd_probe.lua  -- standalone probe of tm_gpu coordinate limits.
-- Run in-game:  wget run http://127.0.0.1:8080/fs/tests/hd_probe.lua
-- Tries filledRectangle at edge coords (origin + full extent) and reports which
-- succeed, so we can pin the coordinate system for the HD term shim. No deps.
local dev = peripheral.find("tm_gpu")
if not dev then print("no tm_gpu found"); return end

dev.refreshSize()
local W, H = 0, 0
for _ = 1, 20 do W, H = dev.getSize(); if W and W > 0 then break end; os.sleep(0.1) end
if not (W and W > 0) then print("0x0 - wall not connected"); return end
pcall(dev.setSize, 64)
W, H = dev.getSize()
print("screen " .. W .. "x" .. H)

local C = 0xFFFFFFFF
local function try(name, fn)
  local ok, e = pcall(fn)
  print(name .. ": " .. (ok and "OK" or ("ERR " .. tostring(e):gsub("^.-:%d+: ", ""))))
end

try("rect(0,0,10,10)",      function() dev.filledRectangle(0, 0, 10, 10, C) end)
try("rect(1,1,10,10)",      function() dev.filledRectangle(1, 1, 10, 10, C) end)
try("rect(0,0,W,H)",        function() dev.filledRectangle(0, 0, W, H, C) end)
try("rect(0,0,W-1,H-1)",    function() dev.filledRectangle(0, 0, W - 1, H - 1, C) end)
try("rect(1,1,W-1,H-1)",    function() dev.filledRectangle(1, 1, W - 1, H - 1, C) end)
try("rect(W-1,H-1,1,1)",    function() dev.filledRectangle(W - 1, H - 1, 1, 1, C) end)
try("rect(W,H,1,1)",        function() dev.filledRectangle(W, H, 1, 1, C) end)
try("text(0,0)",            function() dev.drawText(0, 0, "Hi", C, 0xFF111111, 1) end)
dev.sync()
print("-- done; foto de los OK/ERR porfa --")
