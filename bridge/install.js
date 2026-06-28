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
local function pos()
  local x, y, z = gps.locate(1)
  if x then return { x = x, y = y, z = z } end
  return nil
end
local function announce(t)
  rednet.broadcast({ t = t, name = name, fuel = turtle.getFuelLevel(), pos = pos() }, PROTOCOL)
end
local actions = {
  forward = turtle.forward, back = turtle.back, up = turtle.up, down = turtle.down,
  left = turtle.turnLeft, right = turtle.turnRight,
  dig = turtle.dig, digUp = turtle.digUp, digDown = turtle.digDown,
  refuel = function() return turtle.refuel() end, status = function() return true end,
}
term.clear(); term.setCursorPos(1, 1)
print("PinguOS turtle agent: "..name)
print("Conectada. Esperando ordenes...")
announce("hello")
while true do
  local id, msg = rednet.receive(PROTOCOL, 5)
  if type(msg) == "table" then
    if msg.t == "discover" then
      announce("hello")
    elseif msg.t == "cmd" and msg.action and actions[msg.action] then
      local ok = actions[msg.action]() and true or false
      rednet.send(id, { t = "done", action = msg.action, ok = ok, name = name, fuel = turtle.getFuelLevel(), pos = pos() }, PROTOCOL)
    end
  else
    announce("status")
  end
end
`;
}

module.exports = { installScript, gpsHostScript, turtleAgentScript };
