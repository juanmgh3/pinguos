-- dist/os/apps/fleet.lua  -- mission control for the autonomous turtle fleet.
-- Live dashboard + per-turtle job dispatcher (driven by each turtle's own catalog)
-- + cancel. The old manual D-pad survives as a "debug" submenu.
--
-- Rendering: everything draws into a `window` back-buffer that is flipped visible
-- only once per frame (setVisible), so term.clear is never seen -> no flicker. And
-- redraws are coalesced: rednet messages only update state; we repaint on a fixed
-- tick (and immediately on user input), not once per message.
return {
  id = "fleet", name = "Fleet", icon = "T", color = colors.brown,
  desc = "Controlar turtles",
  run = function(ctx)
    local ui = ctx.ui
    local fleet = ctx.fleet
    local w, h = term.getSize()

    local modemSide
    for _, s in ipairs(peripheral.getNames()) do
      if peripheral.getType(s) == "modem" then modemSide = s; break end
    end
    if not modemSide then
      ui.clear(); ui.titleBar("Fleet")
      ui.text(2, 3, "El computer no tiene modem.", colors.red, colors.black)
      ui.text(2, 4, "Pon un modem y reabre la app.", colors.white, colors.black)
      ui.statusBar("pulsa una tecla para volver"); os.pullEvent("key"); return
    end
    rednet.open(modemSide)

    -- back-buffer: draw off-screen, flip when the frame is done -> no flicker
    local win = window.create(term.current(), 1, 1, w, h, false)
    local prevTerm = term.redirect(win)
    local function frame(drawFn)
      win.setVisible(false)
      drawFn()
      win.setVisible(true)
    end

    ---- fleet state ----------------------------------------------------------
    local turtles = {}
    local scroll = 0      -- index of the first turtle shown (dashboard scroll)
    local LIST_TOP = 2    -- first list row, just under the title bar
    local function ids()
      local list = {}
      for id in pairs(turtles) do list[#list + 1] = id end
      table.sort(list); return list
    end

    local function ingest(id, msg)
      if type(msg) ~= "table" then return end
      if not (msg.t == "hello" or msg.t == "status" or msg.t == "done" or msg.t == "progress") then return end
      local p = turtles[id] or {}
      p.name = msg.name or p.name
      p.role = msg.role or p.role
      if msg.fuel ~= nil then p.fuel = msg.fuel end
      if msg.pos ~= nil then p.pos = msg.pos end
      if msg.inv ~= nil then p.inv = msg.inv end
      if msg.catalog then p.catalog = msg.catalog end
      if msg.status then p.status = msg.status end
      if msg.t == "progress" then
        p.status = "working"; p.job = msg.job
        p.prog = { pct = msg.pct or 0, info = msg.info or "" }
      elseif msg.t == "done" then
        p.status = "idle"; p.job = nil; p.prog = nil
        p.result = (msg.ok and "OK: " or "fallo: ") ..
          tostring(msg.job or msg.action or "") .. " " .. (msg.info or "")
      else -- hello / status
        p.job = msg.job
        if not msg.job then p.prog = nil end
      end
      turtles[id] = p
    end

    ---- visuals --------------------------------------------------------------
    local function statusColor(s)
      if s == "working" then return colors.cyan
      elseif s == "blocked" then return colors.red
      elseif s == "nofuel" then return colors.orange
      else return colors.white end
    end

    -- low fuel stands out: red at empty, orange when it won't last long
    local function fuelColor(fuel)
      if fuel == "unlimited" then return colors.lightGray end
      local n = tonumber(fuel)
      if not n then return colors.lightGray end
      if n <= 0 then return colors.red end
      if n < 80 then return colors.orange end
      return colors.lightGray
    end

    local function drawBar(x, y, bw, pct, col)
      pct = math.max(0, math.min(100, pct or 0))
      ui.fill(x, y, bw, 1, colors.gray)
      local filled = math.floor(bw * pct / 100)
      if filled > 0 then ui.fill(x, y, filled, 1, col or ui.theme.accent) end
    end

    local function bigButton(x, y, label, bg)
      local s = " " .. label .. " "
      ui.text(x, y, s, ui.theme.barFg, bg or ui.theme.accent)
      return { x = x, y = y, w = #s, h = 1 }
    end

    ---- small input helpers --------------------------------------------------
    local function promptParams(job)
      local params = {}
      for _, p in ipairs(job.params or {}) do
        frame(function()
          ui.clear(); ui.titleBar(job.label or job.id)
          ui.text(2, 3, p.label or p.name, colors.white, colors.black)
          ui.text(2, 4, "(enter = " .. tostring(p.default) .. ")", colors.lightGray, colors.black)
        end)
        term.setCursorPos(2, 6); term.setTextColor(colors.white)
        local raw = read()
        local v = (raw == nil or raw == "") and p.default or raw
        if type(p.default) == "number" then v = tonumber(v) or p.default end
        params[p.name] = v
      end
      return params
    end

    ---- manual D-pad (debug) -------------------------------------------------
    local function manualMenu(id)
      local result = ""
      while true do
        local close
        local btns = {}
        frame(function()
          ui.clear()
          close = ui.titleBar("Manual #" .. id)
          ui.text(2, 2, "modo debug - una orden", colors.lightGray, colors.black)
          local layout = {
            { "Adelante", "forward" }, { "Atras", "back" },
            { "Sube", "up" }, { "Baja", "down" },
            { "Izq", "left" }, { "Der", "right" },
            { "Cava", "dig" }, { "CavaAb", "digDown" },
            { "Ataca", "attack" },
          }
          for i, a in ipairs(layout) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            btns[i] = { r = ui.button(2 + col * 13, 4 + row * 2, a[1]), action = a[2] }
          end
          if result ~= "" then ui.text(2, h - 1, result:sub(1, w - 2), ui.theme.accent, colors.black) end
          ui.statusBar("clic orden  -  [x] volver")
        end)
        local ev = { os.pullEvent() }
        if ev[1] == "rednet_message" and ev[4] == fleet.PROTOCOL then
          ingest(ev[2], ev[3])
          if fleet.is(ev[3], "done") then
            result = (ev[3].ok and "OK " or "fallo ") .. tostring(ev[3].action or "")
          end
        elseif ev[1] == "mouse_click" then
          if ui.hit(close, ev[3], ev[4]) then return end
          for _, b in ipairs(btns) do
            if ui.hit(b.r, ev[3], ev[4]) then
              rednet.send(id, fleet.cmd(b.action), fleet.PROTOCOL)
              result = "enviado: " .. b.action
              if ctx.sound then ctx.sound.click() end
            end
          end
        end
      end
    end

    ---- per-turtle command center -------------------------------------------
    local function jobMenu(id)
      local timer = os.startTimer(2)
      while true do
        local t = turtles[id] or {}
        local close, cancelBtn, manualBtn
        local buttons = {}
        frame(function()
          ui.clear()
          close = ui.titleBar(("Turtle #%d %s"):format(id, t.name or ""))
          ui.text(2, 3, "rol: " .. (t.role or "?"), colors.lightGray, colors.black)
          ui.text(2, 4, "estado: " .. (t.status or "?"), statusColor(t.status), colors.black)
          local fs = tostring(t.fuel or "?")
          ui.text(2, 5, "fuel:", colors.white, colors.black)
          ui.text(7, 5, fs, fuelColor(t.fuel), colors.black)
          ui.text(7 + #fs + 1, 5, ("inv:%s%%"):format(t.inv or 0), colors.white, colors.black)
          if t.pos then
            ui.text(2, 6, ("pos:%d,%d,%d"):format(t.pos.x, t.pos.y, t.pos.z), colors.lightGray, colors.black)
          end

          local y = 8
          if t.status == "working" then
            if t.prog then
              drawBar(2, y, math.min(w - 8, 18), t.prog.pct, colors.cyan)
              ui.text(2, y + 1, ((t.prog.pct or 0) .. "%  " .. (t.prog.info or "")):sub(1, w - 2),
                colors.cyan, colors.black)
            end
            cancelBtn = bigButton(2, y + 3, "CANCELAR", colors.red)
            y = y + 5
          else
            ui.text(2, y, "Trabajos:", colors.lightGray, colors.black); y = y + 1
            for _, job in ipairs(t.catalog or {}) do
              if y < h - 3 then
                buttons[#buttons + 1] = { r = ui.button(2, y, job.label or job.id), job = job }
                y = y + 2
              end
            end
            if not t.catalog or #t.catalog == 0 then
              ui.text(2, y, "(esperando catalogo...)", colors.lightGray, colors.black); y = y + 2
            end
          end
          manualBtn = ui.button(2, math.min(y + 1, h - 2), "Manual (debug)")
          if t.result then ui.text(2, h - 1, t.result:sub(1, w - 2), ui.theme.accent, colors.black) end
          ui.statusBar("clic  -  [x] volver a la lista")
        end)

        local ev = { os.pullEvent() }
        if ev[1] == "timer" and ev[2] == timer then
          rednet.broadcast(fleet.discover(), fleet.PROTOCOL); timer = os.startTimer(2)
        elseif ev[1] == "rednet_message" and ev[4] == fleet.PROTOCOL then
          ingest(ev[2], ev[3])
        elseif ev[1] == "mouse_click" then
          local mx, my = ev[3], ev[4]
          if ui.hit(close, mx, my) then return end
          if cancelBtn and ui.hit(cancelBtn, mx, my) then
            rednet.send(id, fleet.cancel(), fleet.PROTOCOL)
            turtles[id].result = "cancelando..."
            if ctx.sound then ctx.sound.click() end
          elseif ui.hit(manualBtn, mx, my) then
            manualMenu(id)
          else
            for _, b in ipairs(buttons) do
              if ui.hit(b.r, mx, my) then
                local params = promptParams(b.job)
                rednet.send(id, fleet.job(b.job.id, params), fleet.PROTOCOL)
                turtles[id] = turtles[id] or {}
                turtles[id].result = "enviado: " .. b.job.id
                if ctx.sound then ctx.sound.click() end
                break
              end
            end
          end
        end
      end
    end

    ---- dashboard (scrollable) -----------------------------------------------
    -- Immediate-mode scroll: `scroll` is just the index of the first visible
    -- turtle. We draw the window list[scroll+1 .. scroll+visible] + a proportional
    -- scrollbar; events only nudge `scroll`, which the main loop clamps.
    local function drawDashboard()
      ui.clear()
      local list = ids()
      local close = ui.titleBar(("Fleet (%d)"):format(#list))
      local rows = {}
      local listBot = h - 1
      local visible = math.max(1, math.floor((listBot - LIST_TOP + 1) / 2)) -- 2 lines/turtle

      if #list == 0 then
        ui.text(2, 3, "Buscando turtles...", colors.lightGray, colors.black)
        ui.text(2, 5, "Enciende cada turtle con:", colors.white, colors.black)
        ui.text(2, 6, "wget run .../turtle", colors.lightGray, colors.black)
        ui.statusBar("R rescan  -  [x] sale")
        return close, rows, visible, 0
      end

      if scroll > math.max(0, #list - visible) then scroll = math.max(0, #list - visible) end
      if scroll < 0 then scroll = 0 end

      local hasBar = #list > visible
      local cw = hasBar and (w - 1) or w   -- reserve the last column for the scrollbar

      for vi = 0, visible - 1 do
        local id = list[scroll + vi + 1]
        if not id then break end
        local t = turtles[id]
        local y = LIST_TOP + vi * 2
        ui.text(2, y, ("#%d %s [%s]"):format(id, t.name or "?", t.role or "?"):sub(1, cw - 1),
          statusColor(t.status), colors.black)
        if t.status == "working" and t.prog then
          local bw = math.min(cw - 9, 12)
          drawBar(2, y + 1, bw, t.prog.pct, colors.cyan)
          ui.text(2 + bw + 1, y + 1, (t.prog.pct or 0) .. "%", colors.cyan, colors.black)
        else
          ui.text(2, y + 1, (t.status or "?"), statusColor(t.status), colors.black)
          local sx = 2 + #(t.status or "?") + 1
          local fs = tostring(t.fuel or "?")
          ui.text(sx, y + 1, ("f:%s inv:%s%%"):format(fs, t.inv or 0):sub(1, cw - sx), colors.lightGray, colors.black)
        end
        rows[#rows + 1] = { y1 = y, y2 = y + 1, id = id }
      end

      if hasBar then  -- proportional scrollbar on the last column
        local trackH = listBot - LIST_TOP + 1
        ui.fill(w, LIST_TOP, 1, trackH, colors.gray)
        local thumbH = math.max(1, math.floor(trackH * visible / #list))
        local thumbY = LIST_TOP + math.floor(trackH * scroll / #list)
        if thumbY + thumbH - 1 > listBot then thumbY = listBot - thumbH + 1 end
        ui.fill(w, thumbY, 1, thumbH, ui.theme.accent)
      end

      ui.statusBar(hasBar
        and ("%d-%d/%d  rueda/flechas/barra  [x]"):format(
          scroll + 1, math.min(scroll + visible, #list), #list)
        or "clic turtle  -  R rescan  -  [x] sale")
      return close, rows, visible, #list
    end

    ---- main loop (coalesced redraws) ----------------------------------------
    local function loop()
      rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
      local disc = os.startTimer(2)    -- discovery broadcast
      local tick = os.startTimer(0.4)  -- redraw refresh (~2.5 fps)
      local close, rows, visible, total
      local function redraw() frame(function() close, rows, visible, total = drawDashboard() end) end
      local function clamp()
        scroll = math.max(0, math.min(scroll, math.max(0, (total or 0) - (visible or 1))))
      end
      redraw()
      while true do
        local ev = { os.pullEvent() }
        local e = ev[1]
        if e == "timer" and ev[2] == disc then
          rednet.broadcast(fleet.discover(), fleet.PROTOCOL); disc = os.startTimer(2)
        elseif e == "timer" and ev[2] == tick then
          redraw(); tick = os.startTimer(0.4)
        elseif e == "rednet_message" and ev[4] == fleet.PROTOCOL then
          ingest(ev[2], ev[3])                       -- state only; the tick repaints
        elseif e == "mouse_scroll" then
          scroll = scroll + ev[2]; clamp(); redraw() -- ev[2] = -1 up / 1 down
        elseif e == "mouse_click" then
          local mx, my = ev[3], ev[4]
          if ui.hit(close, mx, my) then return end
          if total > visible and mx >= w then        -- tap the scrollbar to page
            if my < math.floor((LIST_TOP + h - 1) / 2) then scroll = scroll - visible
            else scroll = scroll + visible end
            clamp(); redraw()
          else
            for _, r in ipairs(rows) do
              if my >= r.y1 and my <= r.y2 then jobMenu(r.id); break end
            end
            redraw()                                 -- repaint after a submenu returns
          end
        elseif e == "key" then
          local k = ev[2]
          if k == keys.r then rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
          elseif k == keys.up then scroll = scroll - 1; clamp(); redraw()
          elseif k == keys.down then scroll = scroll + 1; clamp(); redraw()
          elseif k == keys.pageUp then scroll = scroll - visible; clamp(); redraw()
          elseif k == keys.pageDown then scroll = scroll + visible; clamp(); redraw()
          end
        end
      end
    end

    -- run the loop, then ALWAYS restore the real terminal and close the modem,
    -- even if a draw throws -- otherwise the desktop would render into our buffer.
    local ok, err = pcall(loop)
    term.redirect(prevTerm)
    rednet.close(modemSide)
    if not ok then error(err, 0) end
  end,
}
