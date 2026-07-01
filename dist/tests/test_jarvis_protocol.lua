-- dist/tests/test_jarvis_protocol.lua -- pure agent-protocol parsing.
local protocol = require("jarvis.protocol")

-- parseCall: tool-call sentinel -> {name, argsRaw}; assert fields (comparator is array-only)
local c = protocol.parseCall("@tool fleet_status {}")
T.eq(c and c.name, "fleet_status", "parse name")
T.eq(c and c.argsRaw, "{}", "parse argsRaw")

local c2 = protocol.parseCall("bla bla\n@tool scan {\"r\":8}\nmas texto")
T.eq(c2 and c2.name, "scan", "first sentinel name")
T.eq(c2 and c2.argsRaw, "{\"r\":8}", "first sentinel args")

T.ok(protocol.parseCall("La flota va bien, 3 turtles.") == nil, "final answer -> nil")
T.ok(protocol.parseCall(nil) == nil, "nil input -> nil")
local c3 = protocol.parseCall("   @tool ping   ")
T.eq(c3 and c3.name, "ping", "trims + empty args")
T.eq(c3 and c3.argsRaw, "", "empty argsRaw")

-- renderTools: deterministic ASCII line
local cat = { { name = "fleet_status", params = {}, description = "estado de la flota" } }
T.eq(protocol.renderTools(cat), "- fleet_status() -- estado de la flota", "render one tool")

-- buildPrompt: contains world text, the protocol sentinel, and the tool name
local p = protocol.buildPrompt("BASE FACTS", cat)
T.ok(p:find("BASE FACTS", 1, true) ~= nil, "prompt has world md")
T.ok(p:find("@tool", 1, true) ~= nil, "prompt explains @tool")
T.ok(p:find("fleet_status", 1, true) ~= nil, "prompt lists the tool")
