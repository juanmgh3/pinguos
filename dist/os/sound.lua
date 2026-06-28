-- dist/os/sound.lua  (no-op if no speaker is attached)
local sound = {}

local function spk() return peripheral.find("speaker") end

-- Play a single note safely (instrument, pitch 0-24, volume 0-3).
function sound.note(instrument, pitch, volume)
  local s = spk()
  if s then pcall(s.playNote, instrument, volume or 1, pitch) end
end

-- Short tick when launching/clicking.
function sound.click()
  local s = spk()
  if s then pcall(s.playNote, "hat", 1, 18) end
end

-- Rising bell arpeggio at boot.
function sound.chime()
  local s = spk()
  if not s then return end
  for _, p in ipairs({ 7, 11, 14, 19 }) do
    pcall(s.playNote, "bell", 1, p)
    sleep(0.12)
  end
end

-- Low buzz on error.
function sound.error()
  local s = spk()
  if s then pcall(s.playNote, "bass", 2, 2) end
end

return sound
