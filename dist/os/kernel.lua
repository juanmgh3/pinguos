-- dist/os/kernel.lua
package.path = "/os/?.lua;" .. package.path
local ui = require("ui")
local log = require("log")
local config = require("config")
local appreg = require("appreg")
local text = require("text")
local geo = require("geo")
local sound = require("sound")
local fleet = require("fleet")
local gpu = require("gpu")
local hdterm = require("hdterm")
local focus = require("focus")

local kernel = { version = "0.1.0", pending = nil, hd = nil }
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
    ui = ui, term = term, width = w, height = h, geo = geo, sound = sound, fleet = fleet,
    gpu = kernel.hd and gpu or nil,   -- HD pixel layer for HD-native apps (nil on terminal)
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
  sound.click()
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

-- Paginated desktop: apps split into pages you swipe / arrow between.
local function drawDesktop(apps, page, focusIdx)
  local w, h = term.getSize()
  local cols = math.max(1, math.floor(w / 12))
  local rows = math.max(1, math.floor((h - 9) / 6) + 1)
  local perPage = cols * rows
  local pages = math.max(1, math.ceil(#apps / perPage))
  if page > pages then page = pages elseif page < 1 then page = 1 end
  local wbg = ui.wallpaper(config.get("system", "wallpaper", "negro"))
  ui.fill(1, 1, w, 1, ui.theme.bar)
  ui.fill(1, 1, 1, 1, ui.theme.accent)
  ui.text(3, 1, "PinguOS", ui.theme.accent, ui.theme.bar)
  drawClock()
  local tiles, start = {}, (page - 1) * perPage
  for slot = 1, perPage do
    local app = apps[start + slot]
    if app then
      local n = slot - 1
      local cx = 2 + (n % cols) * 12
      local cy = 3 + math.floor(n / cols) * 6
      ui.iconTile(cx, cy, app.icon or "?", app.color or ui.theme.accent,
                  text.truncate(app.name, 11), (#tiles + 1 == focusIdx), wbg)
      tiles[#tiles + 1] = { r = { x = cx, y = cy, w = 9, h = 3 }, app = app }
    end
  end
  local dots = {}
  if pages > 1 then
    local dx = math.floor((w - (pages * 2 - 1)) / 2) + 1
    for p = 1, pages do
      ui.fill(dx, h - 1, 1, 1, (p == page) and ui.theme.accent or colors.gray)
      dots[#dots + 1] = { r = { x = dx, y = h - 1, w = 1, h = 1 }, page = p }
      dx = dx + 2
    end
    ui.statusBar("flechas <- ->  o  arrastra para cambiar de escritorio")
  else
    ui.statusBar("clic en un icono para abrir")
  end
  return tiles, dots, pages, page
end

-- The desktop event loop (run directly in terminal mode, or under parallel in HD).
local function desktopLoop(apps)
  local page, focusIdx = 1, 1
  while true do
    local tiles, dots, pages, cur = drawDesktop(apps, page, focusIdx)
    page = cur
    if focusIdx > #tiles then focusIdx = #tiles end
    if focusIdx < 1 then focusIdx = 1 end
    local timer = os.startTimer(1)
    local dragX = nil
    local redraw = false
    while not redraw do
      local ev = { os.pullEvent() }
      local name = ev[1]
      if name == "timer" and ev[2] == timer then
        drawClock(); timer = os.startTimer(1)
      elseif name == "mouse_click" then
        local handled = false
        for _, item in ipairs(tiles) do
          if ui.hit(item.r, ev[3], ev[4]) then runApp(item.app); redraw = true; handled = true; break end
        end
        if not handled then
          for _, d in ipairs(dots) do
            if ui.hit(d.r, ev[3], ev[4]) then page = d.page; redraw = true; handled = true; break end
          end
        end
        if not handled then dragX = ev[3] end
      elseif name == "mouse_up" then
        if dragX then
          local dx = ev[3] - dragX
          if dx <= -3 and page < pages then page = page + 1; redraw = true
          elseif dx >= 3 and page > 1 then page = page - 1; redraw = true end
          dragX = nil
        end
      elseif name == "key" then
        local k = ev[2]
        if k == keys.enter then
          if tiles[focusIdx] then runApp(tiles[focusIdx].app); redraw = true end
        elseif k == keys.up or k == keys.down or k == keys.left or k == keys.right then
          local dir = (k == keys.up and "up") or (k == keys.down and "down")
                   or (k == keys.left and "left") or "right"
          local rects = {}
          for i, t in ipairs(tiles) do rects[i] = t.r end
          local ni = focus.spatial(rects, focusIdx, dir)
          if ni ~= focusIdx then
            focusIdx = ni; redraw = true
          elseif dir == "right" and page < pages then
            page = page + 1; focusIdx = 1; redraw = true
          elseif dir == "left" and page > 1 then
            page = page - 1; focusIdx = 1; redraw = true
          end
        end
      elseif name == "term_resize" then
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

-- HD daemon: coalesced flush (~20fps, avoids issue #8 lag) + translate the
-- monitor's pixel touch into a cell-space mouse_click the desktop/apps understand.
local function hdDaemon()
  local t = os.startTimer(0.05)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == t then
      kernel.hd.flush(); t = os.startTimer(0.05)
    elseif ev[1] == "tm_monitor_touch" then
      local cx, cy = kernel.hd.mapPixel(ev[3], ev[4])
      os.queueEvent("mouse_click", 1, cx, cy)
    end
  end
end

function kernel.run()
  config.init()
  local accent = config.get("system", "accent")
  if accent then ui.setTheme({ accent = accent }) end
  -- HD edition: if a Tom's GPU is wired, redirect the whole OS onto the wall.
  if gpu.attach() then
    kernel.hd = hdterm.new(gpu, { scale = config.get("system", "hdScale", 1) })
    term.redirect(kernel.hd.term)
    -- Physical keyboard (Tom's tm_keyboard): switch it to native CC key/char
    -- events so the desktop and every app get real typing for free -- no app
    -- changes. Gated on HD because its capture GUI hides the term: a keyboard
    -- with no wall to read is typing blind. Wrapped: a peripheral must not crash
    -- the OS if setFireNativeEvents is missing on another mod version.
    local kb = peripheral.find("tm_keyboard")
    if kb and pcall(function() kb.setFireNativeEvents(true) end) then
      kernel.kb = true
    end
  end
  local function main()
    ui.splash(kernel.version)
    sound.chime()
    local surface = kernel.hd and (kernel.kb and " (HD+KB)" or " (HD)") or ""
    log.system("PinguOS " .. kernel.version .. surface .. " booting")
    desktopLoop(discover())
  end
  if kernel.hd then
    parallel.waitForAny(main, hdDaemon)
  else
    main()
  end
end

return kernel
