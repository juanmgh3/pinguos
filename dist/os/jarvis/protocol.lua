-- dist/os/jarvis/protocol.lua -- pure agent-protocol helpers (no CC globals).
-- Loaded by require() in tests (local 5.4) and by loadfile() in-game; uses neither
-- require nor any CC API, so it works under both. Unit-tested in test_jarvis_protocol.
local protocol = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Parse a Claude reply. The FIRST line that (trimmed) matches `@tool <name> <args>`
-- is a tool-call -> {name, argsRaw}. No such line -> nil (the reply is the final
-- answer). JSON of argsRaw is decoded by the caller (CC textutils), keeping this pure.
function protocol.parseCall(text)
  if type(text) ~= "string" then return nil end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local name, argsRaw = trim(line):match("^@tool%s+(%S+)%s*(.-)$")
    if name then return { name = name, argsRaw = trim(argsRaw) } end
  end
  return nil
end

-- Render the catalogue as deterministic ASCII lines for the system prompt.
function protocol.renderTools(catalog)
  local out = {}
  for _, t in ipairs(catalog or {}) do
    out[#out + 1] = "- " .. t.name .. "(" .. table.concat(t.params or {}, ", ")
                 .. ") -- " .. (t.description or "")
  end
  return table.concat(out, "\n")
end

-- Full system prompt: WORLD.md + tools + the fixed protocol instructions.
function protocol.buildPrompt(worldMd, catalog)
  return table.concat({
    worldMd or "",
    "",
    "## Tools",
    "To use a tool, reply with EXACTLY one line and nothing else:",
    "@tool <name> <json-args>   (example: @tool fleet_status {})",
    "The system then replies with: @result <json>. Continue from there.",
    "When you have the final answer, reply in plain natural language (no @tool line).",
    "",
    "Available tools:",
    protocol.renderTools(catalog),
  }, "\n")
end

return protocol
