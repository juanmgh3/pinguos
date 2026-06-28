-- dist/os/config.lua
local config = {}
local PATH = "/cfg/system.json"
local data = nil

local function load()
  data = {}
  if fs.exists(PATH) then
    local h = fs.open(PATH, "r"); local raw = h.readAll(); h.close()
    local ok, parsed = pcall(textutils.unserialiseJSON, raw)
    if ok and type(parsed) == "table" then
      data = parsed
    else
      pcall(fs.delete, PATH .. ".bad")
      pcall(fs.move, PATH, PATH .. ".bad") -- keep the corrupt file for inspection
    end
  end
end

function config.init() if not data then load() end end

function config.get(ns, key, default)
  config.init()
  local sect = data[ns]
  if type(sect) == "table" and sect[key] ~= nil then return sect[key] end
  return default
end

function config.save()
  config.init()
  if not fs.exists("/cfg") then fs.makeDir("/cfg") end
  local tmp = PATH .. ".tmp"
  local h = fs.open(tmp, "w"); h.write(textutils.serialiseJSON(data)); h.close()
  if fs.exists(PATH) then fs.delete(PATH) end
  fs.move(tmp, PATH)
end

function config.set(ns, key, value)
  config.init()
  if type(data[ns]) ~= "table" then data[ns] = {} end
  data[ns][key] = value
  config.save()
end

return config
