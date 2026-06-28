-- dist/os/apps/gps.lua
return {
  id = "gps", name = "GPS", icon = "+", color = colors.lime,
  desc = "Mapa y waypoints",
  run = function(ctx)
    local ui = ctx.ui
    local geo = require("geo")

    if not peripheral.find("modem") then
      ui.clear(); ui.titleBar("GPS")
      ui.text(2, 3, "Sin modem.", colors.red, colors.black)
      ui.text(2, 4, "Pon un ender modem en el pocket.", colors.white, colors.black)
      ui.statusBar("pulsa una tecla para volver")
      os.pullEvent("key"); return
    end

    local waypoints = ctx.config.get("waypoints", {})
    local scale = ctx.config.get("scale", 4)
    local trail = {}
    local pos, prev, heading = nil, nil, "-"

    local function locate()
      local x, y, z = gps.locate(1)
      if x then
        prev = pos
        pos = { x = x, y = y, z = z }
        if prev and geo.distance(prev, pos) >= 1 then
          heading = geo.heading(prev, pos)
          trail[#trail + 1] = pos
          if #trail > 200 then table.remove(trail, 1) end
        end
      else
        pos = nil
      end
    end

    local function draw()
      ui.clear()
      local close = ui.titleBar("GPS")
      local w, h = term.getSize()
      if pos then
        ui.text(2, 3, ("X %d  Y %d  Z %d"):format(
          math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)), colors.white, colors.black)
        ui.text(2, 4, "Rumbo: " .. heading .. "  (escala x" .. scale .. ")",
          ui.theme.accent, colors.black)
      else
        ui.text(2, 3, "Sin senal GPS", colors.red, colors.black)
        ui.text(2, 4, "(fuera de rango o sin constelacion)", colors.lightGray, colors.black)
      end

      local mpx, mpy, mpw, mph = 2, 6, w - 3, h - 7
      ui.panel(mpx, mpy, mpw, mph, "Mapa")
      local ix, iy, iw, ih = mpx + 1, mpy + 1, mpw - 2, mph - 2
      if pos then
        for _, p in ipairs(trail) do
          local cx, cy = geo.toMinimap(pos, p, iw, ih, scale)
          if cx then ui.text(ix + cx - 1, iy + cy - 1, ".", colors.gray, colors.black) end
        end
        for name, wp in pairs(waypoints) do
          local cx, cy = geo.toMinimap(pos, wp, iw, ih, scale)
          if cx then ui.text(ix + cx - 1, iy + cy - 1, name:sub(1, 1):upper(), colors.yellow, colors.black) end
        end
        local pcx, pcy = geo.toMinimap(pos, pos, iw, ih, scale)
        if pcx then ui.text(ix + pcx - 1, iy + pcy - 1, "@", ui.theme.accent, colors.black) end
      end

      ui.statusBar("M marcar  W lista  C limpiar  [x] salir")
      return close
    end

    local function markWaypoint()
      if not pos then return end
      ui.clear(); ui.titleBar("Marcar waypoint")
      ui.text(2, 3, "Nombre del sitio:", colors.white, colors.black)
      term.setCursorPos(2, 5); term.setTextColor(colors.white)
      local name = read()
      if name and #name > 0 then
        waypoints[name] = { x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z) }
        ctx.config.set("waypoints", waypoints)
      end
    end

    local function listWaypoints()
      ui.clear(); ui.titleBar("Waypoints")
      local y, any = 3, false
      for name, wp in pairs(waypoints) do
        any = true
        local d = pos and (math.floor(geo.distance(pos, wp)) .. " bloques") or "?"
        local dir = pos and geo.compass(pos, wp) or "-"
        ui.text(2, y, name .. ": " .. d .. " " .. dir, colors.white, colors.black)
        y = y + 1
      end
      if not any then ui.text(2, 3, "(ningun waypoint aun)", colors.lightGray, colors.black) end
      ui.statusBar("pulsa una tecla para volver")
      os.pullEvent("key")
    end

    locate()
    local tid = os.startTimer(1)
    while true do
      local close = draw()
      local ev = { os.pullEvent() }
      if ev[1] == "timer" and ev[2] == tid then
        locate(); tid = os.startTimer(1)
      elseif ev[1] == "mouse_click" and ui.hit(close, ev[3], ev[4]) then
        return
      elseif ev[1] == "key" then
        local k = ev[2]
        if k == keys.q then return
        elseif k == keys.m then markWaypoint()
        elseif k == keys.w then listWaypoints()
        elseif k == keys.c then trail = {} end
      end
    end
  end,
}
