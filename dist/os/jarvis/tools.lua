-- dist/os/jarvis/tools.lua -- JARVIS tool catalogue. Each tool: {name, description,
-- params, run(args, ctx) -> table}. Inc 0 ships one read-only tool: fleet_status.
local tools = { list = {}, byName = {} }

local function register(t) tools.list[#tools.list + 1] = t; tools.byName[t.name] = t end

register({
  name = "fleet_status",
  description = "estado actual de la flota de turtles (id, nombre, rol, estado, fuel)",
  params = {},
  run = function(_, ctx)
    local fleet = ctx.fleet
    local side
    for _, s in ipairs(peripheral.getNames()) do
      if peripheral.getType(s) == "modem" then side = s; break end
    end
    if not side then return { error = "no hay modem en el computer" } end
    rednet.open(side)
    rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
    local seen, deadline = {}, os.startTimer(2)
    while true do
      local ev, a, b, c = os.pullEvent()
      if ev == "timer" and a == deadline then break
      elseif ev == "rednet_message" and c == fleet.PROTOCOL and type(b) == "table" and b.name then
        seen[a] = { id = a, name = b.name, role = b.role, status = b.status, fuel = b.fuel }
      end
    end
    rednet.close(side)
    local list = {}
    for _, t in pairs(seen) do list[#list + 1] = t end
    return { count = #list, turtles = list }
  end,
})

return tools
