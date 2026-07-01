-- dist/tests/claude_smoke.lua  -- run in-game: wget run http://127.0.0.1:8080/fs/tests/claude_smoke.lua
-- Confirms ClaudeCraft's Lua API: is _G.claude present, what functions/events exist,
-- and can we do one round-trip? Mirrors kb_smoke.lua. NOT a unit test.
print("=== ClaudeCraft smoke ===")
print("_G.claude type: " .. type(_G.claude))
if type(_G.claude) ~= "table" then
  print("NOT FOUND. Is ClaudeCraft installed + a key/channel set? (/claudecraft ...)")
  return
end
print("keys on _G.claude:")
for k, v in pairs(_G.claude) do print("  ." .. tostring(k) .. " = " .. type(v)) end

print("Sending a test message (watch for events for 20s)...")
-- Try the reference call shapes; adjust if your build differs:
local ok, err = pcall(function()
  if _G.claude.ask then
    print("ask() returned: " .. tostring(_G.claude.ask("Say OK in 3 words.")))
  elseif _G.claude.startChannel then
    local ch = _G.claude.startChannel("You are a test. Reply briefly.")
    print("startChannel -> " .. type(ch))
    if ch and ch.sendMessage then ch.sendMessage("Say OK in 3 words.")
    elseif _G.claude.sendMessage then _G.claude.sendMessage("Say OK in 3 words.") end
  elseif _G.claude.sendMessage then
    _G.claude.sendMessage("Say OK in 3 words.")
  end
end)
if not ok then print("call error: " .. tostring(err)) end

local t = os.startTimer(20)
while true do
  local ev = { os.pullEventRaw() }
  if ev[1] == "timer" and ev[2] == t then break end
  if tostring(ev[1]):find("claude") then
    print("EVENT " .. ev[1] .. " | " .. tostring(ev[2]):sub(1, 60))
  end
  if ev[1] == "terminate" then break end
end
print("=== done ===")
