-- dist/os/apps/fleet.lua  -- command center for connected turtles
return {
  id = "fleet", name = "Fleet", icon = "T", color = colors.brown,
  desc = "Controlar turtles",
  run = function(ctx)
    local ui = ctx.ui
    local fleet = ctx.fleet

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

    local turtles = {}
    local sel = 1

    local function ids()
      local list = {}
      for id in pairs(turtles) do list[#list + 1] = id end
      table.sort(list)
      return list
    end

    local function ingest(id, msg)
      if type(msg) ~= "table" then return end
      if msg.t == "hello" or msg.t == "status" or msg.t == "done" then
        local prev = turtles[id] or {}
        turtles[id] = { name = msg.name or prev.name, fuel = msg.fuel or prev.fuel, pos = msg.pos or prev.pos }
      end
    end

    local function commandMenu(id)
      local actions = {
        { "Adelante", "forward" }, { "Atras", "back" },
        { "Sube", "up" }, { "Baja", "down" },
        { "Gira Izq", "left" }, { "Gira Der", "right" },
        { "Cava", "dig" }, { "Recarga", "refuel" },
      }
      local result = ""
      while true do
        ui.clear()
        local close = ui.titleBar("Turtle #" .. id)
        local t = turtles[id] or {}
        ui.text(2, 3, ("%s  fuel:%s"):format(t.name or "?", tostring(t.fuel or "?")), colors.white, colors.black)
        local btns = {}
        for i, a in ipairs(actions) do
          local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
          btns[i] = { r = ui.button(2 + col * 12, 5 + row * 2, a[1]), action = a[2] }
        end
        if result ~= "" then ui.text(2, 14, result, ui.theme.accent, colors.black) end
        ui.statusBar("clic una orden  -  [x] volver a la lista")
        local ev = { os.pullEvent() }
        if ev[1] == "rednet_message" and ev[4] == fleet.PROTOCOL then
          ingest(ev[2], ev[3])
          if fleet.is(ev[3], "done") then result = (ev[3].ok and "OK: " or "FALLO: ") .. tostring(ev[3].action) end
        elseif ev[1] == "mouse_click" then
          if ui.hit(close, ev[3], ev[4]) then return end
          for _, b in ipairs(btns) do
            if ui.hit(b.r, ev[3], ev[4]) then
              rednet.send(id, fleet.cmd(b.action), fleet.PROTOCOL)
              result = "enviado: " .. b.action .. " ..."
              if ctx.sound then ctx.sound.click() end
            end
          end
        end
      end
    end

    rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
    local timer = os.startTimer(2)
    while true do
      ui.clear()
      local close = ui.titleBar("Fleet")
      local list = ids()
      if #list == 0 then
        ui.text(2, 3, "Buscando turtles...", colors.lightGray, colors.black)
        ui.text(2, 5, "Enciendelas con el agente:", colors.white, colors.black)
        ui.text(2, 6, "wget run .../turtle", colors.lightGray, colors.black)
      else
        if sel > #list then sel = #list elseif sel < 1 then sel = 1 end
        for i, id in ipairs(list) do
          local t = turtles[id]
          local mark = (i == sel) and ">" or " "
          ui.text(2, 2 + i, ("%s #%d %s  f:%s"):format(mark, id, t.name or "?", tostring(t.fuel or "?")),
            (i == sel) and ui.theme.accent or colors.white, colors.black)
        end
      end
      ui.statusBar("flechas mueven - ENTER ordenes - R rebuscar - [x] sale")
      local ev = { os.pullEvent() }
      if ev[1] == "timer" and ev[2] == timer then
        rednet.broadcast(fleet.discover(), fleet.PROTOCOL); timer = os.startTimer(2)
      elseif ev[1] == "rednet_message" and ev[4] == fleet.PROTOCOL then
        ingest(ev[2], ev[3])
      elseif ev[1] == "mouse_click" and ui.hit(close, ev[3], ev[4]) then
        rednet.close(modemSide); return
      elseif ev[1] == "key" then
        if ev[2] == keys.up and sel > 1 then sel = sel - 1
        elseif ev[2] == keys.down and sel < #list then sel = sel + 1
        elseif ev[2] == keys.r then rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
        elseif ev[2] == keys.enter and list[sel] then commandMenu(list[sel]) end
      end
    end
  end,
}
