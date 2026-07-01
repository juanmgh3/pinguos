-- dist/os/jarvis/agent.lua -- the agent loop: NL -> (tool-call)* -> final answer.
-- Dependencies are INJECTED via agent.init (no require inside app-loaded files).
local agent = {}
local MAX_TURNS = 6
local protocol, claudecc, tools

function agent.init(p, c, t) protocol, claudecc, tools = p, c, t end

function agent.run(ctx, worldMd, userMsg, emit)
  if not claudecc.available() then emit("error", "ClaudeCraft no detectado"); return end
  local session = claudecc.open(protocol.buildPrompt(worldMd, tools.list))
  local ok, err = pcall(function()
    local reply = claudecc.send(session, userMsg)
    for _ = 1, MAX_TURNS do
      local call = protocol.parseCall(reply)
      if not call then emit("answer", reply); return end
      emit("tool", call.name)
      local tool = tools.byName[call.name]
      local result
      if not tool then
        result = { error = "tool desconocida: " .. call.name }
      else
        local args = textutils.unserialiseJSON(call.argsRaw) or {}
        local rok, r = pcall(tool.run, args, ctx)
        result = rok and r or { error = tostring(r) }
      end
      local resJson = textutils.serialiseJSON(result)
      emit("result", resJson)
      reply = claudecc.send(session, "@result " .. resJson)
    end
    emit("answer", reply) -- turn cap hit: surface the last reply
  end)
  claudecc.close(session)
  if not ok then emit("error", tostring(err)) end
end

return agent
