-- dist/tests/claude_smoke.lua -- ClaudeCraft probe, round 3 (post-pivot).
-- Round 2 proved sendMessage wants a TABLE. The channel server source shows
-- POST /message accepts {userMessage | messages | system}, reply returns via SSE
-- (reply -> done). GOAL: find which Lua table shape sendMessage takes AND capture the
-- CC event name the mod fires with the reply, via one real round-trip. NOT a unit test.
print("=== ClaudeCraft smoke v3 ===")
if type(_G.claude) ~= "table" then print("NO _G.claude"); return end

local function try(label, fn, ...)
  if type(fn) ~= "function" then print(label .. ": (absent)"); return false end
  local ok, r = pcall(fn, ...)
  print(label .. ": " .. (ok and ("ok " .. tostring(r):sub(1, 40)) or ("ERR " .. tostring(r):sub(1, 55))))
  return ok, r
end

_G.claude.startChannel(false)
-- The brain connects asynchronously; poll until ready (up to ~10s).
local ready = false
for _ = 1, 20 do
  if _G.claude.isChannelReady and _G.claude.isChannelReady() then ready = true; break end
  os.sleep(0.5)
end
print("isChannelReady: " .. tostring(ready))

-- Try the likely table shapes; stop at the first that does NOT error (userMessage first,
-- it is the server's canonical field).
local msg = "Reply with exactly: OK JARVIS ONLINE"
local shapes = {
  { name = "{userMessage=}", val = { userMessage = msg } },
  { name = "{messages={{role,content}}}", val = { messages = { { role = "user", content = msg } } } },
  { name = "{text=}", val = { text = msg } },
  { name = "{prompt=}", val = { prompt = msg } },
  { name = "{message=}", val = { message = msg } },
}
local accepted
for _, s in ipairs(shapes) do
  if try("sendMessage " .. s.name, _G.claude.sendMessage, s.val) then accepted = s.name; break end
end
if not accepted then print("no table shape accepted -> signature differs"); return end
print("accepted shape: " .. accepted)

print("Listening 30s for the reply event (ignoring input noise)...")
local t = os.startTimer(30)
local n = 0
while true do
  local ev = { os.pullEventRaw() }
  if ev[1] == "timer" and ev[2] == t then break end
  if ev[1] == "terminate" then break end
  local name = tostring(ev[1])
  if name ~= "timer" and name ~= "key" and name ~= "key_up" and name ~= "char" and name ~= "mouse_click" and name ~= "mouse_up" then
    n = n + 1
    print(("EV%d %s | 2=%s | 3=%s"):format(n, name, tostring(ev[2]):sub(1, 42), tostring(ev[3]):sub(1, 18)))
    if n >= 25 then print("(25 events, stopping)"); break end
  end
end
print("=== done v3 ===")
