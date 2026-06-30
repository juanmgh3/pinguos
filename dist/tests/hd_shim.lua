-- dist/tests/hd_shim.lua  -- in-game test of the HD term redirect (hdterm.new).
-- Needs /os/hdterm.lua + /os/gpu.lua installed: run the Update app FIRST, then:
--   wget run http://127.0.0.1:8080/fs/tests/hd_shim.lua
-- Renders plain term.* calls onto the HD wall via term.redirect, to prove the shim.
local gpu = dofile("/os/gpu.lua")
local hdterm = dofile("/os/hdterm.lua")
if not gpu.attach() then print("no tm_gpu found"); return end

local emu = hdterm.new(gpu, { scale = 2 })
local w, h = emu.size()

local old = term.redirect(emu.term)
term.setBackgroundColor(colors.black)
term.clear()
term.setTextColor(colors.cyan);   term.setCursorPos(2, 2); term.write("PinguOS HD shim")
term.setTextColor(colors.white);  term.setCursorPos(2, 4); term.write("term.redirect -> HD")
term.setTextColor(colors.green);  term.setCursorPos(2, 6); term.write("0123456789 abcdef XYZ")
term.setTextColor(colors.yellow); term.setCursorPos(2, 8); term.write("se lee nitido?")
emu.flush()
term.redirect(old)

print("HD term redirect: " .. w .. "x" .. h .. " celdas - mira la pared")
