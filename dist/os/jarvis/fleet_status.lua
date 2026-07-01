-- dist/os/jarvis/fleet_status.lua -- headless CLI: report the turtle fleet state.
-- The JARVIS brain runs this via run_command to answer fleet questions. Read-only.
-- Reuses fleet.lua (loadfile, no require -- unavailable outside the kernel). ASCII output.
local fleet = assert(loadfile("/os/fleet.lua"))()

local side
for _, s in ipairs(peripheral.getNames()) do
  if peripheral.getType(s) == "modem" then side = s; break end
end
if not side then print("fleet_status: no modem on this computer"); return end

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

local n = 0
for id, t in pairs(seen) do
  n = n + 1
  print(("#%d %s [%s] %s fuel=%s"):format(
    math.floor(id), t.name or "?", t.role or "?", t.status or "?", tostring(t.fuel or "?")))
end
if n == 0 then print("fleet: no turtles responding on " .. fleet.PROTOCOL)
else print(("fleet: %d turtle(s) online"):format(n)) end
