-- turtle/agent.lua  -- PinguOS autonomous turtle agent. Runs ON the turtle, loaded
-- from /pingu by the startup the mini-installer writes. Detects its role from the
-- equipped tool, discovers its jobs from disk, and runs whole jobs on its own while
-- staying answerable (status/cancel) thanks to `parallel`.
if not turtle then print("Esto es para una TURTLE."); return end

local BASE = "/pingu"
local PROTOCOL = "pingufleet"

local function loadMod(path)
  local fn, err = loadfile(path)
  if not fn then error("no pude cargar " .. path .. ": " .. tostring(err)) end
  return fn()
end

local roles   = loadMod(BASE .. "/lib/roles.lua")
local nav     = loadMod(BASE .. "/lib/nav.lua")
local makeApi = loadMod(BASE .. "/lib/api.lua")

-- discover jobs from /pingu/jobs
local jobs = {}
if fs.exists(BASE .. "/jobs") then
  for _, fn in ipairs(fs.list(BASE .. "/jobs")) do
    if fn:match("%.lua$") then
      local ok, job = pcall(loadMod, BASE .. "/jobs/" .. fn)
      if ok and type(job) == "table" and job.id then jobs[job.id] = job end
    end
  end
end

local function openModem()
  for _, s in ipairs(peripheral.getNames()) do
    if peripheral.getType(s) == "modem" then rednet.open(s); return true end
  end
  return false
end
if not openModem() then print("La turtle no tiene modem."); return end

-- reconnect on boot
do
  local f = fs.open("startup.lua", "w")
  f.write('shell.run("' .. BASE .. '/agent.lua")\n')
  f.close()
end

local name = os.getComputerLabel() or ("turtle" .. os.getComputerID())

---- role detection ----------------------------------------------------------
local function detectRole()
  local function fromSide(getter)
    local ok, d = pcall(getter)
    if ok and type(d) == "table" then return roles.fromDetail(d) end
    return nil
  end
  return fromSide(turtle.getEquippedRight) or fromSide(turtle.getEquippedLeft)
end

local role = detectRole()
if (not role) and fs.exists(BASE .. "/role") then
  local rf = fs.open(BASE .. "/role", "r"); role = rf.readAll(); rf.close()
end
if not role or not roles.isValid(role) then
  term.clear(); term.setCursorPos(1, 1)
  print("No detecte herramienta. Rol manual:")
  print(" 1) mineria   2) tala   3) ataque")
  print(" 4) excavacion  5) granja  6) generico")
  io.write("> ")
  role = ({ ["1"] = "mineria", ["2"] = "tala", ["3"] = "ataque",
            ["4"] = "excavacion", ["5"] = "granja" })[read()] or "generico"
end
do local rf = fs.open(BASE .. "/role", "w"); rf.write(role); rf.close() end

---- catalog for this role ---------------------------------------------------
local function jobAllowed(job)
  return job.roles and (job.roles.any or job.roles[role]) and true or false
end
local catalog = {}
for _, job in pairs(jobs) do
  if jobAllowed(job) then
    catalog[#catalog + 1] = { id = job.id, label = job.label or job.id, params = job.params or {} }
  end
end
table.sort(catalog, function(a, b) return a.id < b.id end)

---- telemetry (GPS is cached so the idle loop doesn't pay locate() every redraw) --
local lastPos = nil
local function refreshPos()
  local x, y, z = gps.locate(1)
  lastPos = x and { x = x, y = y, z = z } or nil
  return lastPos
end
local function pos() return lastPos end
local function invPct()
  local used = 0
  for s = 1, 16 do if turtle.getItemCount(s) > 0 then used = used + 1 end end
  return math.floor(used / 16 * 100)
end

local state = "idle"     -- idle | working | blocked | nofuel
local curJob = nil
local prog = { pct = 0, info = "" }
local lastAction = "-"

local function redraw()
  term.clear(); term.setCursorPos(1, 1)
  if term.isColour() then term.setTextColor(colors.lime) end
  print("== PinguOS turtle ==")
  if term.isColour() then term.setTextColor(colors.white) end
  print("Nombre: " .. name .. "  [" .. role .. "]")
  print("Fuel:   " .. tostring(turtle.getFuelLevel()) .. "   Inv: " .. invPct() .. "%")
  local p = pos()
  print("Pos:    " .. (p and (p.x .. "," .. p.y .. "," .. p.z) or "sin GPS"))
  print("Estado: " .. state .. (curJob and ("  job:" .. curJob) or ""))
  if curJob then print("        " .. prog.pct .. "% " .. prog.info) end
  print("Ultima: " .. lastAction)
  print("")
  print("Conectada. Esperando ordenes...")
end

local function announce(t)
  rednet.broadcast({
    t = t, name = name, role = role, status = state,
    fuel = turtle.getFuelLevel(), pos = pos(), job = curJob, inv = invPct(),
    catalog = (t == "hello") and catalog or nil,
  }, PROTOCOL)
end

---- run a job with a concurrent cancel/heartbeat listener -------------------
local function runJob(boss, job, params)
  state = "working"; curJob = job.id; prog = { pct = 0, info = "" }
  refreshPos(); redraw(); announce("status")

  local cancelled = false
  local result = { ok = false, info = "" }

  local api = makeApi({
    params = params, nav = nav, protocol = PROTOCOL, name = name, job = job.id, pos = pos,
    shouldCancel = function() return cancelled end,
    setStatus = function(s) state = s end,
    setProg = function(pct, info) prog = { pct = pct or 0, info = info or "" } end,
    redraw = redraw,
  })

  local function worker()
    local ok, a, b = pcall(job.run, api)
    if ok then
      result.ok = (a ~= false); result.info = tostring(b or "")
    else
      result.ok = false; result.info = "error: " .. tostring(a); state = "blocked"
    end
  end
  local function listener()
    while true do
      local _, m = rednet.receive(PROTOCOL)
      if type(m) == "table" then
        if m.t == "cancel" then cancelled = true; return
        elseif m.t == "discover" or m.t == "status" then announce("status") end
      end
    end
  end

  parallel.waitForAny(worker, listener)

  local ok = result.ok and not cancelled
  lastAction = job.id .. (cancelled and " cancelado" or (ok and " ok" or " fallo"))
  state = "idle"; curJob = nil; refreshPos()
  rednet.send(boss, {
    t = "done", job = job.id, ok = ok,
    info = cancelled and "cancelado" or result.info,
    name = name, role = role, fuel = turtle.getFuelLevel(), pos = pos(),
  }, PROTOCOL)
  redraw()
end

---- manual single action (debug mode) --------------------------------------
local MANUAL = {
  forward = turtle.forward, back = turtle.back, up = turtle.up, down = turtle.down,
  left = turtle.turnLeft, right = turtle.turnRight,
  dig = turtle.dig, digUp = turtle.digUp, digDown = turtle.digDown,
  attack = turtle.attack, attackUp = turtle.attackUp, attackDown = turtle.attackDown,
}
local MOVES = { forward = true, back = true, up = true, down = true }
local function manualAction(boss, action)
  if MOVES[action] then
    local lvl = turtle.getFuelLevel()
    if lvl ~= "unlimited" and lvl == 0 then
      for s = 1, 16 do turtle.select(s); if turtle.refuel(1) then break end end
      turtle.select(1)
    end
  end
  local fn = MANUAL[action]
  local ok = fn and (fn() and true or false) or false
  lastAction = action .. (ok and " ok" or " fallo"); refreshPos(); redraw()
  rednet.send(boss, {
    t = "done", action = action, ok = ok,
    name = name, role = role, fuel = turtle.getFuelLevel(), pos = pos(),
  }, PROTOCOL)
end

---- main loop ---------------------------------------------------------------
refreshPos(); redraw(); announce("hello")
while true do
  local boss, msg = rednet.receive(PROTOCOL, 5)
  if type(msg) == "table" then
    if msg.t == "discover" then
      announce("hello")
    elseif msg.t == "job" and jobs[msg.job] then
      runJob(boss, jobs[msg.job], msg.params or {})
    elseif msg.t == "cmd" and msg.action and MANUAL[msg.action] then
      manualAction(boss, msg.action)
    end
  else
    refreshPos(); announce("status")   -- idle heartbeat
  end
end
