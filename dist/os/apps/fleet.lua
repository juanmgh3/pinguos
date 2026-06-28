-- dist/os/apps/fleet.lua  -- command center for connected turtles (role-aware)
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
    local function ids()
      local list = {}
      for id in pairs(turtles) do list[#list + 1] = id end
      table.sort(list); return list
    end
    local function ingest(id, msg)
      if type(msg) ~= "table" then return end
      if msg.t == "hello" or msg.t == "status" or msg.t == "done" then
        local p = turtles[id] or {}
        turtles[id] = { name = msg.name or p.name, role = msg.role or p.role,
                        fuel = msg.fuel or p.fuel, pos = msg.pos or p.pos }
      end
    end

    local function prompt(title, q)
      ui.clear(); ui.titleBar(title)
      ui.text(2, 3, q, colors.white, colors.black)
      term.setCursorPos(2, 5); term.setTextColor(colors.white)
      return read()
    end

    local function menuFor(role)
      local c = {
        { "Adelante", "forward" }, { "Atras", "back" }, { "Sube", "up" },
        { "Baja", "down" }, { "Gira Izq", "left" }, { "Gira Der", "right" },
      }
      local tunnel = false
      if role == "ataque" then
        c[#c + 1] = { "Atacar", "attack" }; c[#c + 1] = { "Atacar arr", "attackUp" }; c[#c + 1] = { "Atacar aba", "attackDown" }
      elseif role == "mineria" then
        c[#c + 1] = { "Cava", "dig" }; tunnel = true
      elseif role == "cava" then
        c[#c + 1] = { "Cava", "dig" }; c[#c + 1] = { "Cava arr", "digUp" }; c[#c + 1] = { "Cava aba", "digDown" }
      else
        c[#c + 1] = { "Cava", "dig" }; c[#c + 1] = { "Atacar", "attack" }; tunnel = true
      end
      c[#c + 1] = { "Recarga", "refuel" }
      return c, tunnel
    end

    local function commandMenu(id)
      local result = ""
      while true do
        local t = turtles[id] or {}
        local cmds, tunnel = menuFor(t.role)
        ui.clear()
        local close = ui.titleBar("Turtle #" .. id .. " [" .. (t.role or "?") .. "]")
        ui.text(2, 3, ("%s  fuel:%s"):format(t.name or "?", tostring(t.fuel or "?")), colors.white, colors.black)
        local btns = {}
        for i, a in ipairs(cmds) do
          local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
          btns[i] = { r = ui.button(2 + col * 14, 5 + row * 2, a[1]), action = a[2] }
        end
        local mineBtn
        if tunnel then mineBtn = ui.button(2, 5 + math.ceil(#cmds / 2) * 2, "Excavar tunel") end
        if result ~= "" then ui.text(2, 17, result, ui.theme.accent, colors.black) end
        ui.statusBar("clic una orden  -  [x] volver a la lista")
        local ev = { os.pullEvent() }
        if ev[1] == "rednet_message" and ev[4] == fleet.PROTOCOL then
          ingest(ev[2], ev[3])
          if fleet.is(ev[3], "done") then
            result = (ev[3].ok and "OK: " or "FALLO: ") .. tostring(ev[3].action) .. " " .. (ev[3].info or "")
          end
        elseif ev[1] == "mouse_click" then
          if ui.hit(close, ev[3], ev[4]) then return end
          if mineBtn and ui.hit(mineBtn, ev[3], ev[4]) then
            local n = tonumber(prompt("Excavar tunel", "Cuantos bloques cavar?"))
            if n and n > 0 then rednet.send(id, fleet.cmd("mine", n), fleet.PROTOCOL); result = "enviado: tunel " .. n end
          else
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
    end

    rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
    local timer = os.startTimer(2)
    while true do
      ui.clear()
      local close = ui.titleBar("Fleet")
      local list = ids()
      local rows = {}
      if #list == 0 then
        ui.text(2, 3, "Buscando turtles...", colors.lightGray, colors.black)
        ui.text(2, 5, "Enciendelas con el agente:", colors.white, colors.black)
        ui.text(2, 6, "wget run .../turtle", colors.lightGray, colors.black)
      else
        ui.text(2, 2, "Clic en una turtle:", colors.lightGray, colors.black)
        for i, id in ipairs(list) do
          local t = turtles[id]
          local y = 3 + i
          ui.text(2, y, ("#%d %s [%s] f:%s"):format(id, t.name or "?", t.role or "?", tostring(t.fuel or "?")),
            colors.white, colors.black)
          rows[#rows + 1] = { y = y, id = id }
        end
      end
      ui.statusBar("clic una turtle  -  R rebuscar  -  [x] sale")
      local ev = { os.pullEvent() }
      if ev[1] == "timer" and ev[2] == timer then
        rednet.broadcast(fleet.discover(), fleet.PROTOCOL); timer = os.startTimer(2)
      elseif ev[1] == "rednet_message" and ev[4] == fleet.PROTOCOL then
        ingest(ev[2], ev[3])
      elseif ev[1] == "mouse_click" then
        if ui.hit(close, ev[3], ev[4]) then rednet.close(modemSide); return end
        for _, r in ipairs(rows) do
          if ev[4] == r.y then commandMenu(r.id); break end
        end
      elseif ev[1] == "key" and ev[2] == keys.r then
        rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
      end
    end
  end,
}
