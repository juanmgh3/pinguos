-- dist/os/jarvis/claudecc.lua -- the ONLY file that knows ClaudeCraft's API.
-- Reference API (CONFIRM/CORRECT via dist/tests/claude_smoke.lua, Plan Task 0):
--   _G.claude.startChannel(systemPrompt) -> channel ; channel.sendMessage(text)
--   events: "claude_text"(partial chunk) / "claude_done"(full text).
-- If Task 0 shows a different shape (e.g. _G.claude.ask(text) -> string), implement
-- send() with that instead -- nothing else in JARVIS needs to change.
local claudecc = {}

function claudecc.available()
  return type(_G.claude) == "table"
end

function claudecc.open(systemPrompt)
  local ch = _G.claude.startChannel and _G.claude.startChannel(systemPrompt) or _G.claude
  return { ch = ch, system = systemPrompt }
end

-- Send a message; block until the reply is complete; return the full text.
function claudecc.send(session, text)
  local ch = session.ch
  if ch.sendMessage then ch.sendMessage(text)
  elseif _G.claude.sendMessage then _G.claude.sendMessage(text) end
  local buf = {}
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "claude_text" then buf[#buf + 1] = tostring(ev[2] or "")
    elseif ev[1] == "claude_done" then
      return (ev[2] ~= nil and ev[2] ~= "") and tostring(ev[2]) or table.concat(buf)
    end
  end
end

function claudecc.close(session)
  if session.ch and session.ch.close then session.ch.close() end
end

return claudecc
