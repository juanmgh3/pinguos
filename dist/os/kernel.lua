-- dist/os/kernel.lua
package.path = "/os/?.lua;" .. package.path
local ui = require("ui")
local log = require("log")
local config = require("config")
local appreg = require("appreg")
local text = require("text")
local geo = require("geo")

local kernel = { version = "0.1.0", pending = nil }
local APP_DIR = "/os/apps"

local function loadApp(path)
  local fn, err = loadfile(path)
  if not fn then return false, err end
  local ok, res = pcall(fn)
  if not ok then return false, res end
  return true, res
end

local function discover()
  local files = {}
  if fs.exists(APP_DIR) then
    for _, name in ipairs(fs.list(APP_DIR)) do
      if name:match("%.lua$") then
        files[#files + 1] = { id = name:gsub("%.lua$", ""), path = APP_DIR .. "/" .. name }
      end
    end
  end
  local apps, errs = appreg.collect(files, loadApp)
  for _, e in ipairs(errs) do log.system("app '" .. e.id .. "' skipped: " .. e.err) end
  return apps
end

local function makeCtx(app)
  local w, h = term.getSize()
  return {
    ui = ui, term = term, width = w, height = h, geo = geo,
    log = function(msg) log.app(app.id, msg) end,
    config = {
      get = function(k, d) return config.get(app.id, k, d) end,
      set = function(k, v) return config.set(app.id, k, v) end,
    },
    sys = {
      version = kernel.version, theme = ui.theme,
      openApp = function(id) kernel.pending = id end,
      getSetting = function(k, d) return config.get("system", k, d) end,
      setSetting = function(k, v) return config.set("system", k, v) end,
    },
  }
end

local function runApp(app)
  ui.clear()
  local ok, err = pcall(app.run, makeCtx(app))
  if not ok then
    log.app(app.id, "CRASH: " .. tostring(err))
    ui.clear()
    local w = term.getSize()
    ui.text(2, 2, "App '" .. app.name .. "' fallo:", ui.theme.error, ui.theme.bg)
    local y = 4
    for _, line in ipairs(text.wrap(tostring(err), w - 2)) do
      ui.text(2, y, line, ui.theme.fg, ui.theme.bg); y = y + 1
    end
    ui.text(2, y + 1, "Pulsa una tecla para volver", ui.theme.barFg, ui.theme.bg)
    os.pullEvent("key")
  end
end

local function drawClock()
  local w = term.getSize()
  local clk = textutils.formatTime(os.time(), true)
  ui.text(w - #clk, 1, clk, ui.theme.barFg, ui.theme.bar)
end

local function drawDesktop(apps)
  ui.clear()
  local w = term.getSize()
  ui.fill(1, 1, w, 1, ui.theme.bar)
  ui.fill(1, 1, 1, 1, ui.theme.accent)
  ui.text(3, 1, "PinguOS", ui.theme.accent, ui.theme.bar)
  drawClock()
  local regions, cols = {}, math.max(1, math.floor(w / 12))
  for i, app in ipairs(apps) do
    local n = i - 1
    local cx = 2 + (n % cols) * 12
    local cy = 3 + math.floor(n / cols) * 6
    ui.iconTile(cx, cy, app.icon or "?", app.color or ui.theme.accent,
                text.truncate(app.name, 11))
    regions[#regions + 1] = { r = { x = cx, y = cy, w = 9, h = 3 }, app = app }
  end
  ui.statusBar("clic en un icono para abrir")
  return regions
end

function kernel.run()
  config.init()
  local accent = config.get("system", "accent")
  if accent then ui.setTheme({ accent = accent }) end
  ui.splash(kernel.version)
  log.system("PinguOS " .. kernel.version .. " booting")
  local apps = discover()
  while true do
    local regions = drawDesktop(apps)
    local timer = os.startTimer(1)
    local redraw = false
    while not redraw do
      local ev = { os.pullEvent() }
      if ev[1] == "timer" and ev[2] == timer then
        drawClock(); timer = os.startTimer(1)
      elseif ev[1] == "mouse_click" then
        for _, item in ipairs(regions) do
          if ui.hit(item.r, ev[3], ev[4]) then runApp(item.app); redraw = true; break end
        end
      elseif ev[1] == "term_resize" then
        redraw = true
      end
      if kernel.pending then
        for _, app in ipairs(apps) do
          if app.id == kernel.pending then runApp(app); break end
        end
        kernel.pending = nil; redraw = true
      end
    end
  end
end

return kernel
