-- dist/tests/claude_smoke.lua  -- run in-game: wget run http://127.0.0.1:8080/fs/tests/claude_smoke.lua
-- ClaudeCraft API probe, round 2. Round 1 revealed the key set and that
-- startChannel(string) errors "boolean expected" -> startChannel takes a BOOLEAN.
-- Now: pass the boolean, complete a round-trip, and CAPTURE THE REPLY EVENT NAME(S)
-- (the one thing round 1 could not reach). NOT a unit test.
print("=== ClaudeCraft smoke v2 ===")
if type(_G.claude) ~= "table" then print("NO _G.claude"); return end

local function try(label, fn, ...)
  if type(fn) ~= "function" then print(label .. ": (absent)"); return false end
  local ok, r = pcall(fn, ...)
  print(label .. ": " .. (ok and tostring(r):sub(1, 80) or ("ERR " .. tostring(r):sub(1, 80))))
  return ok, r
end

try("isApiKeyConfigured", _G.claude.isApiKeyConfigured)
try("getModel", _G.claude.getModel)
try("getPersonality", _G.claude.getPersonality)   -- is the system prompt set in-game?
try("isChannelReady before", _G.claude.isChannelReady)

-- startChannel takes a boolean. false = simplest (likely native tools/web OFF -> plain
-- chat, which is what our @tool text protocol wants). Flip to true later if needed.
try("startChannel(false)", _G.claude.startChannel, false)
try("isChannelReady after", _G.claude.isChannelReady)
try("sendMessage", _G.claude.sendMessage, "Say OK in exactly three words.")

print("Listening 25s for ANY non-timer event (the reply)...")
local t = os.startTimer(25)
local n = 0
while true do
  local ev = { os.pullEventRaw() }
  if ev[1] == "timer" and ev[2] == t then break end
  if ev[1] == "terminate" then break end
  if ev[1] ~= "timer" then
    n = n + 1
    print(("EV%d %s | 2=%s | 3=%s"):format(
      n, tostring(ev[1]), tostring(ev[2]):sub(1, 50), tostring(ev[3]):sub(1, 24)))
    if n >= 30 then print("(30 events, stopping)"); break end
  end
end
print("=== done v2 ===")
