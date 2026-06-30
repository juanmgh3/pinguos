-- dist/tests/kb_smoke.lua  -- in-game diagnostic for the Tom's tm_keyboard input path.
-- Run in-game on the computer that has the keyboard/dongle next to it:
--   wget run http://127.0.0.1:8080/fs/tests/kb_smoke.lua
-- It instruments the 3 boundaries (peripheral present -> setFireNativeEvents ->
-- events arriving) and prints raw evidence. Captures events BLIND for 20 s (you
-- won't see this terminal while the keyboard GUI is open) then dumps on close.
-- Not part of the installed OS (the manifest skips tests/).

local unpack = table.unpack or unpack
local WINDOW = 20  -- seconds to capture

print("=== PinguOS keyboard smoke test ===")

-- Boundary 1: is the peripheral there at all?
local names = peripheral.getNames()
print("peripherals present: " .. (#names > 0 and table.concat(names, ", ") or "(none)"))

local kb = peripheral.find("tm_keyboard")
if not kb then
  print("tm_keyboard: NONE FOUND")
  print(">> The keyboard/dongle is not seen as a peripheral. Check it touches a")
  print("   face of THIS computer (or is on a wired modem that is turned on).")
  return
end
print("tm_keyboard: FOUND (" .. tostring(peripheral.getName(kb)) .. ")")

local methods = {}
for _, m in ipairs(peripheral.getMethods and peripheral.getMethods(peripheral.getName(kb)) or {}) do
  methods[#methods + 1] = m
end
print("methods: " .. (#methods > 0 and table.concat(methods, ", ") or "(unknown)"))

-- Boundary 2: can we switch it to native CC events?
local ok, err = pcall(function() kb.setFireNativeEvents(true) end)
print("setFireNativeEvents(true): " .. (ok and "ok" or ("ERROR -> " .. tostring(err))))

-- Boundary 3: do events actually arrive?
print("")
print(">> You have " .. WINDOW .. " s. Open the keyboard GUI now:")
print("   - Keyboard block: right-click it.")
print("   - Portable: right-click it in hand (bind to the Portable")
print("     Dongle first with shift+right-click if you have not).")
print("   Then press keys / type a few letters, and press Esc.")
print("   Results appear here when the timer ends.")
print("")

local counts, kbEvents = {}, {}
local function fmt(e)
  local parts = {}
  for i = 2, #e do parts[#parts + 1] = tostring(e[i]) end
  return table.concat(parts, " ")
end

local kbNames = {
  key = true, key_up = true, char = true, paste = true,
  terminate = true, shutdown = true, reboot = true,
  tm_keyboard_key = true, tm_keyboard_key_up = true,
  tm_keyboard_char = true, tm_keyboard_paste = true,
  portable_connect = true, portable_disconnect = true,
}

local timer = os.startTimer(WINDOW)
while true do
  local e = { os.pullEventRaw() }
  if e[1] == "timer" and e[2] == timer then break end
  counts[e[1]] = (counts[e[1]] or 0) + 1
  if kbNames[e[1]] and #kbEvents < 60 then
    kbEvents[#kbEvents + 1] = e[1] .. "  " .. fmt(e)
  end
end

print("=== captured in " .. WINDOW .. " s ===")
local total = 0
for name, n in pairs(counts) do
  total = total + n
  print(("  %-22s x%d"):format(name, n))
end
if total == 0 then
  print("  (NO events at all -> the GUI sent nothing. Did the capture")
  print("   window open? Portable: is it bound to the Dongle and in range?)")
end
if #kbEvents > 0 then
  print("--- keyboard events (in order) ---")
  for _, line in ipairs(kbEvents) do print("  " .. line) end
end
