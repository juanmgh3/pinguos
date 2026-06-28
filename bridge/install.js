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

module.exports = { installScript, gpsHostScript };
