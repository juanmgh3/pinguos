// bridge/install.js
function installScript(baseUrl, token) {
  return `-- PinguOS installer (auto-generated)
local BASE = "${baseUrl}"
local TOKEN = "${token}"
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
-- Merge the bridge token into the OS settings file. Read-modify-write, so an
-- update does not wipe accent, wallpaper or hdScale.
local CFG = "/cfg/system.json"
local cfg = {}
if fs.exists(CFG) then
  local ch = fs.open(CFG, "r"); local craw = ch.readAll(); ch.close()
  local cok, parsed = pcall(textutils.unserialiseJSON, craw)
  if cok and type(parsed) == "table" then
    cfg = parsed
  else
    -- Corrupt config: keep it for inspection, same as the OS loader (config.lua),
    -- rather than clobbering it. cfg stays {} and a fresh file is written below.
    pcall(fs.delete, CFG..".bad")
    pcall(fs.move, CFG, CFG..".bad")
  end
end
if type(cfg.system) ~= "table" then cfg.system = {} end
cfg.system.bridgeToken = TOKEN
if not fs.exists("/cfg") then fs.makeDir("/cfg") end
local ctmp = CFG..".tmp"
local cf = fs.open(ctmp, "w"); cf.write(textutils.serialiseJSON(cfg)); cf.close()
if fs.exists(CFG) then fs.delete(CFG) end
fs.move(ctmp, CFG)
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

// Turtle firmware installer: wget run http://127.0.0.1:8080/turtle (run on a turtle).
// Instead of one giant embedded agent string, this pulls the real turtle modules
// (agent + lib + jobs) from the bridge into /pingu, then starts the agent. The agent
// writes its own startup so it reconnects on reboot. Same proven flow as the OS
// installer (manifest + per-file fetch), just scoped to the turtle firmware.
function turtleBootstrapScript(baseUrl) {
  return `-- PinguOS turtle installer (auto-generated)
if not turtle then print("Esto es para una TURTLE."); return end
local BASE = "${baseUrl}"
local function getJSON(url)
  local h = http.get(url); if not h then error("no manifest: "..url) end
  local s = h.readAll(); h.close(); return textutils.unserialiseJSON(s)
end
local function dirOf(p) return p:match("^(.*)/[^/]+$") end
print("PinguOS turtle: bajando firmware...")
local m = getJSON(BASE.."/turtle-manifest")
for _, f in ipairs(m.files) do
  local h = http.get(BASE.."/turtle-fs"..f.path)
  if not h then error("download failed: "..f.path) end
  local data = h.readAll(); h.close()
  local dest = "/pingu"..f.path
  local d = dirOf(dest); if d and d ~= "" and not fs.exists(d) then fs.makeDir(d) end
  local out = fs.open(dest, "w"); out.write(data); out.close()
  print("  "..dest)
end
print("Firmware "..(m.version or "?").." instalado. Arrancando agente...")
sleep(1)
shell.run("/pingu/agent.lua")
`;
}

module.exports = { installScript, gpsHostScript, turtleBootstrapScript };
