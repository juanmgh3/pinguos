-- claude.lua -- talk to your local claude-bridge from inside Minecraft (CC: Tweaked)
--
-- Setup:
--   1. On the in-game computer:  edit claude   then paste this, Ctrl -> Save -> Exit
--   2. Run the bridge on your PC: node claude-bridge.js
--   3. In the computer, just type: claude
--
-- Requires:
--   * CC:T http enabled (it is by default)
--   * CC:T http rules allowing 127.0.0.1 (NOT allowed by default -- see notes)

local URL = "http://127.0.0.1:8080"

if not http then
  printError("HTTP API is disabled. Set http.enabled = true in the CC:T config.")
  return
end

term.clear()
term.setCursorPos(1, 1)
print("Claude bridge ready. Type a message ('exit' to quit).")
print(string.rep("-", 40))

while true do
  write("\nyou > ")
  local msg = read()
  if msg == "exit" or msg == "quit" then break end

  if #msg > 0 then
    local body = textutils.serialiseJSON({ prompt = msg })
    local res, errmsg = http.post(URL, body, { ["Content-Type"] = "application/json" })

    if not res then
      printError("request failed: " .. tostring(errmsg))
      printError("(is the bridge running? is 127.0.0.1 allowed in CC:T config?)")
    else
      local raw = res.readAll()
      res.close()
      local ok, data = pcall(textutils.unserialiseJSON, raw)
      if ok and data and data.text then
        print("\nclaude > " .. data.text)
      elseif ok and data and data.error then
        printError("bridge error: " .. tostring(data.error))
      else
        print("\nclaude > " .. raw) -- fallback: print whatever came back
      end
    end
  end
end

print("bye.")
