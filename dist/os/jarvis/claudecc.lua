-- dist/os/jarvis/claudecc.lua -- the ONLY file that knows ClaudeCraft's _G.claude API.
-- Verified from the channel server source (2026-07-01): startChannel(bool)->true;
-- sendMessage({userMessage=text}); the brain's reply surfaces as a CC event whose name
-- contains "claude" (exact name pinned on the first in-game run). No require here (this is
-- loaded via loadfile in the app). See specs/pinguos/jarvis-core.md.
local claudecc = {}

local REPLY_TIMEOUT = 120  -- the brain may think + call native tools before it replies

function claudecc.available()
  return type(_G.claude) == "table"
end

-- Start the channel and wait until the brain is connected/ready (it connects async).
function claudecc.open()
  if _G.claude.startChannel then pcall(_G.claude.startChannel, false) end
  local ready = false
  for _ = 1, 40 do
    if _G.claude.isChannelReady and _G.claude.isChannelReady() then ready = true; break end
    os.sleep(0.25)
  end
  return { ready = ready }
end

-- Send a user message; block until the brain replies; return replyText, eventName.
-- The reply is a CC event whose name contains "claude"; we take that event's LONGEST string
-- field (the reply text beats any short id/marker). onEvent(name, ev) (optional) fires for
-- every matched event so the app can print the raw shape once and pin it exactly.
function claudecc.send(session, text, onEvent)
  _G.claude.sendMessage({ userMessage = text })
  local timeout = os.startTimer(REPLY_TIMEOUT)
  while true do
    local ev = { os.pullEvent() }
    local name = tostring(ev[1])
    if name == "timer" and ev[2] == timeout then
      return nil, "timeout"
    elseif name:lower():find("claude") then
      if onEvent then pcall(onEvent, name, ev) end
      local best
      for i = 2, #ev do
        if type(ev[i]) == "string" and (not best or #ev[i] > #best) then best = ev[i] end
      end
      if best and #best > 0 then return best, name end
      -- a claude event with no text (e.g. a bare "done"): keep waiting for the text one
    end
  end
end

function claudecc.close(_)
  if _G.claude and _G.claude.stopChannel then pcall(_G.claude.stopChannel) end
end

return claudecc
