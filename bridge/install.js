// bridge/install.js
function installScript(baseUrl) {
  return `-- PinguOS installer (auto-generated)
local BASE = "${baseUrl}"
local function getJSON(url)
  local h = http.get(url); if not h then error("no manifest: "..url) end
  local s = h.readAll(); h.close(); return textutils.unserialiseJSON(s)
end
local function dirOf(p) return p:match("^(.*)/[^/]+$") end
print("PinguOS: fetching manifest...")
local m = getJSON(BASE.."/manifest")
for _, f in ipairs(m.files) do
  local url = BASE.."/fs"..f.path
  local h = http.get(url); if not h then error("download failed: "..f.path) end
  local data = h.readAll(); h.close()
  local d = dirOf(f.path); if d and d ~= "" and not fs.exists(d) then fs.makeDir(d) end
  local out = fs.open(f.path, "w"); out.write(data); out.close()
  print("  "..f.path)
end
print("PinguOS "..(m.version or "?").." installed. Rebooting...")
sleep(1)
os.reboot()
`;
}

// One-command GPS host setup: wget run http://127.0.0.1:8080/gpshost
// Auto-detects position on a command computer; asks manually otherwise.
function gpsHostScript() {
  return `-- PinguOS GPS host setup (auto-generated)
local function hasModem()
  for _, s in ipairs(peripheral.getNames()) do
    if peripheral.getType(s) == "modem" then return true end
  end
  return false
end
term.clear(); term.setCursorPos(1, 1)
print("== PinguOS GPS host ==")
if not hasModem() then
  print("No modem. Attach a wireless/ender modem, then re-run.")
  return
end
local x, y, z
if commands and commands.getBlockPosition then
  x, y, z = commands.getBlockPosition()
  print("Command computer: auto-detected "..x..","..y..","..z)
else
  print("This computer's coords (F3 -> look at the block):")
  io.write("X: "); x = tonumber(read())
  io.write("Y: "); y = tonumber(read())
  io.write("Z: "); z = tonumber(read())
end
if not (x and y and z) then print("Invalid coords, aborted."); return end
local f = fs.open("startup.lua", "w")
f.write("term.clear(); term.setCursorPos(1,1)\\n")
f.write(("print('PinguOS GPS beacon')\\nprint('Pos %d %d %d - leave running')\\nprint('')\\n"):format(x, y, z))
f.write(("shell.run('gps','host',%d,%d,%d)\\n"):format(x, y, z))
f.close()
print(("Beacon set at %d %d %d. Rebooting..."):format(x, y, z))
sleep(1); os.reboot()
`;
}

// Turtle fleet agent: wget run http://127.0.0.1:8080/turtle (run on a turtle).
function turtleAgentScript() {
  return `-- PinguOS turtle agent (auto-generated)
if not turtle then print("Esto es para una TURTLE."); return end
local PROTOCOL = "pingufleet"
local function openModem()
  for _, s in ipairs(peripheral.getNames()) do
    if peripheral.getType(s) == "modem" then rednet.open(s); return true end
  end
  return false
end
if not openModem() then print("La turtle no tiene modem."); return end
local f = fs.open("startup.lua", "w")           -- reconnect on boot
f.write('shell.run("wget","run","http://127.0.0.1:8080/turtle")\\n')
f.close()
local name = os.getComputerLabel() or ("turtle"..os.getComputerID())
local role
if fs.exists("/pingu-role") then
  local rf = fs.open("/pingu-role", "r"); role = rf.readAll(); rf.close()
else
  term.clear(); term.setCursorPos(1, 1)
  print("Rol de esta turtle:")
  print("  1) mineria   2) ataque   3) cava   4) generico")
  io.write("> ")
  role = ({ ["1"] = "mineria", ["2"] = "ataque", ["3"] = "cava" })[read()] or "generico"
  local rf = fs.open("/pingu-role", "w"); rf.write(role); rf.close()
end
local lastAction = "-"
local function pos()
  local x, y, z = gps.locate(1)
  if x then return { x = x, y = y, z = z } end
  return nil
end
local function ensureFuel()
  if turtle.getFuelLevel() == "unlimited" then return true end
  if turtle.getFuelLevel() > 0 then return true end
  for s = 1, 16 do turtle.select(s); if turtle.refuel(1) then turtle.select(1); return true end end
  turtle.select(1); return false
end
local function move(fn) if ensureFuel() then return fn() end return false end
local actions = {
  forward = function() return move(turtle.forward) end,
  back = function() return move(turtle.back) end,
  up = function() return move(turtle.up) end,
  down = function() return move(turtle.down) end,
  left = turtle.turnLeft, right = turtle.turnRight,
  dig = turtle.dig, digUp = turtle.digUp, digDown = turtle.digDown,
  attack = turtle.attack, attackUp = turtle.attackUp, attackDown = turtle.attackDown,
  refuel = function() return ensureFuel() end, status = function() return true end,
}
local function redraw()
  term.clear(); term.setCursorPos(1, 1)
  if term.isColour() then term.setTextColor(colors.lime) end
  print("== PinguOS turtle ==")
  if term.isColour() then term.setTextColor(colors.white) end
  print("Nombre: "..name.."  ["..role.."]")
  print("Fuel:   "..tostring(turtle.getFuelLevel()))
  local p = pos()
  print("Pos:    "..(p and (p.x..","..p.y..","..p.z) or "sin GPS"))
  print("Ultima: "..lastAction)
  print("")
  print("Conectada. Esperando ordenes...")
end
local function announce(t)
  rednet.broadcast({ t = t, name = name, role = role, fuel = turtle.getFuelLevel(), pos = pos() }, PROTOCOL)
end
redraw(); announce("hello")
while true do
  local id, msg = rednet.receive(PROTOCOL, 5)
  if type(msg) == "table" then
    if msg.t == "discover" then
      announce("hello")
    elseif msg.t == "cmd" and msg.action == "mine" then
      local n = tonumber(msg.arg) or 1
      local done = 0
      for i = 1, n do
        turtle.dig()
        if move(turtle.forward) then done = done + 1 else break end
      end
      lastAction = "tunel "..done.."/"..n; redraw()
      rednet.send(id, { t = "done", action = "mine", ok = (done == n), info = done.."/"..n, name = name, fuel = turtle.getFuelLevel(), pos = pos() }, PROTOCOL)
    elseif msg.t == "cmd" and msg.action and actions[msg.action] then
      local ok = actions[msg.action]() and true or false
      lastAction = msg.action..(ok and " ok" or " sin fuel?"); redraw()
      rednet.send(id, { t = "done", action = msg.action, ok = ok, name = name, fuel = turtle.getFuelLevel(), pos = pos() }, PROTOCOL)
    end
  else
    announce("status")
  end
end
`;
}

module.exports = { installScript, gpsHostScript, turtleAgentScript };
