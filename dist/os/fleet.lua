-- dist/os/fleet.lua  -- rednet protocol for the turtle fleet (pure, testable)
local fleet = {}

fleet.PROTOCOL = "pingufleet"

function fleet.discover() return { t = "discover" } end
function fleet.hello(name, fuel, pos) return { t = "hello", name = name, fuel = fuel, pos = pos } end
function fleet.status(fuel, pos) return { t = "status", fuel = fuel, pos = pos } end
function fleet.cmd(action, arg) return { t = "cmd", action = action, arg = arg } end
function fleet.done(action, ok, info) return { t = "done", action = action, ok = ok, info = info } end

-- autonomy layer: delegate a whole job, cancel it, and the turtle's progress reports
function fleet.job(id, params) return { t = "job", job = id, params = params or {} } end
function fleet.cancel() return { t = "cancel" } end
function fleet.progress(job, pct, info) return { t = "progress", job = job, pct = pct, info = info } end
function fleet.catalog(jobs) return { t = "catalog", jobs = jobs } end

function fleet.is(msg, t) return type(msg) == "table" and msg.t == t end

-- single manual actions a turtle agent understands (the Fleet app's "debug" D-pad).
-- Jobs are discovered dynamically from each turtle's reported catalog, not listed here.
fleet.ACTIONS = {
  "forward", "back", "up", "down", "left", "right",
  "dig", "digUp", "digDown", "attack", "attackUp", "attackDown",
}
function fleet.isAction(a)
  for _, v in ipairs(fleet.ACTIONS) do if v == a then return true end end
  return false
end

return fleet
