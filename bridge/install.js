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
  print("No modem. Attach a wireless/ender modem to a side, then re-run.")
  return
end
print("This computer's coords (press F3, look at the block):")
io.write("X: "); local x = tonumber(read())
io.write("Y: "); local y = tonumber(read())
io.write("Z: "); local z = tonumber(read())
if not (x and y and z) then print("Invalid numbers, aborted."); return end
local f = fs.open("startup.lua", "w")
f.write(("shell.run('gps','host',%d,%d,%d)\\n"):format(x, y, z))
f.close()
print(("Saved. Hosting at %d %d %d on reboot."):format(x, y, z))
print("Rebooting..."); sleep(1); os.reboot()
`;
}

module.exports = { installScript, gpsHostScript };
