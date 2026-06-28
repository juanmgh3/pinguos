-- dist/os/apps/gpshost.lua  -- turn THIS computer into a GPS beacon
return {
  id = "gpshost", name = "GPS Host", icon = "H", color = colors.purple,
  desc = "Crear una baliza de la constelacion",
  run = function(ctx)
    local ui = ctx.ui
    local function wait() ui.statusBar("pulsa una tecla para volver"); os.pullEvent("key") end

    ui.clear()
    local close = ui.titleBar("GPS Host")
    if not peripheral.find("modem") then
      ui.text(2, 3, "Sin modem.", colors.red, colors.black)
      ui.text(2, 4, "Pon un ender modem y reabre la app.", colors.white, colors.black)
      wait(); return
    end

    ui.text(2, 3, "Este computer sera una BALIZA dedicada.", colors.white, colors.black)
    local x, y, z
    if commands and commands.getBlockPosition then
      x, y, z = commands.getBlockPosition()
      ui.text(2, 5, "Command computer detectado:", colors.lime, colors.black)
      ui.text(2, 6, ("posicion auto = %d %d %d"):format(x, y, z), colors.lime, colors.black)
    else
      ui.text(2, 4, "Mete sus coords (F3, mira el bloque):", colors.lightGray, colors.black)
      local function ask(label, row)
        ui.text(2, row, label, colors.white, colors.black)
        term.setCursorPos(2 + #label + 1, row); term.setTextColor(colors.white)
        return tonumber(read())
      end
      x = ask("X:", 6); y = ask("Y:", 7); z = ask("Z:", 8)
      if not (x and y and z) then
        ui.text(2, 10, "Numeros invalidos.", colors.red, colors.black); wait(); return
      end
    end

    ui.text(2, 10, ("Crear baliza en %d %d %d?"):format(x, y, z), colors.yellow, colors.black)
    local yes = ui.button(2, 12, "Si, crear baliza")
    local no = ui.button(21, 12, "Cancelar")
    ui.statusBar("ojo: este computer pasa a ser solo baliza (sin PinguOS)")
    while true do
      local ev = { os.pullEvent() }
      if ev[1] == "mouse_click" then
        if ui.hit(close, ev[3], ev[4]) or ui.hit(no, ev[3], ev[4]) then return end
        if ui.hit(yes, ev[3], ev[4]) then
          local f = fs.open("startup.lua", "w")
          f.write("term.clear(); term.setCursorPos(1,1)\n")
          f.write(("print('PinguOS GPS beacon')\nprint('Pos %d %d %d - leave running')\nprint('')\n"):format(x, y, z))
          f.write(("shell.run('gps','host',%d,%d,%d)\n"):format(x, y, z))
          f.close()
          if ctx.sound then ctx.sound.chime() end
          ui.clear(); ui.titleBar("GPS Host")
          ui.text(2, 3, "Baliza creada. Reiniciando...", colors.lime, colors.black)
          sleep(1); os.reboot()
        end
      end
    end
  end,
}
