-- dist/os/fleet.lua  -- rednet protocol for the turtle fleet (pure, testable)
local fleet = {}

fleet.PROTOCOL = "pingufleet"

function fleet.discover() return { t = "discover" } end
function fleet.hello(name, fuel, pos) return { t = "hello", name = name, fuel = fuel, pos = pos } end
function fleet.status(fuel, pos) return { t = "status", fuel = fuel, pos = pos } end
function fleet.cmd(action, arg) return { t = "cmd", action = action, arg = arg } end
function fleet.done(action, ok, info) return { t = "done", action = action, ok = ok, info = info } end

function fleet.is(msg, t) return type(msg) == "table" and msg.t == t end

-- actions a turtle agent understands
fleet.ACTIONS = {
  "forward", "back", "up", "down", "left", "right",
  "dig", "digUp", "digDown", "refuel", "status",
}
function fleet.isAction(a)
  for _, v in ipairs(fleet.ACTIONS) do if v == a then return true end end
  return false
end

return fleet
