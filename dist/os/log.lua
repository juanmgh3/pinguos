-- dist/os/log.lua
local log = {}
local DIR = "/logs"

local function stamp()
  local ok, s = pcall(os.date, "[%H:%M:%S] ")
  if ok and s then return s end
  return "[" .. tostring(os.clock()) .. "] "
end

function log.write(name, msg)
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  local h = fs.open(DIR .. "/" .. name .. ".log", "a")
  if h then h.writeLine(stamp() .. tostring(msg)); h.close() end
end

function log.system(msg) log.write("system", msg) end
function log.app(id, msg) log.write(id, msg) end

return log
