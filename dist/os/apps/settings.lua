-- dist/os/apps/settings.lua
return {
  id = "settings", name = "Ajustes", icon = "*", color = colors.orange,
  desc = "Tema, fondo y conexion",
  run = function(ctx)
    local ui = ctx.ui
    local accents = { colors.cyan, colors.lime, colors.orange, colors.magenta, colors.red }
    local anames  = { "cyan", "lime", "orange", "magenta", "red" }
    local walls = ui.wallpapers or { "negro" }
    while true do
      ui.clear()
      local close = ui.titleBar("Ajustes")

      ui.text(2, 3, "Color de acento:", colors.white, colors.black)
      local abtns = {}
      for i = 1, #accents do
        local x = 2 + (i - 1) * 9
        ui.fill(x, 4, 8, 1, accents[i])
        ui.text(x, 4, " " .. anames[i], colors.black, accents[i])
        abtns[i] = { x = x, y = 4, w = 8, h = 1 }
      end

      ui.text(2, 6, "Fondo de pantalla:", colors.white, colors.black)
      local wbtns, x = {}, 2
      for i = 1, #walls do
        local b = ui.button(x, 7, walls[i])
        wbtns[i] = b
        x = x + b.w + 1
      end

      ui.text(2, 9, "Bridge URL:", colors.white, colors.black)
      ui.text(2, 10, ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080"),
              colors.lightGray, colors.black)
      local editBtn = ui.button(2, 12, "Editar URL")

      ui.statusBar("acento / fondo / URL  -  [x] salir")
      local ev = { os.pullEvent() }
      if ev[1] == "mouse_click" then
        if ui.hit(close, ev[3], ev[4]) then return end
        for i = 1, #abtns do
          if ui.hit(abtns[i], ev[3], ev[4]) then
            ui.setTheme({ accent = accents[i] }); ctx.sys.setSetting("accent", accents[i])
          end
        end
        for i = 1, #wbtns do
          if ui.hit(wbtns[i], ev[3], ev[4]) then ctx.sys.setSetting("wallpaper", walls[i]) end
        end
        if ui.hit(editBtn, ev[3], ev[4]) then
          ui.clear(); ui.titleBar("Bridge URL")
          ui.text(2, 3, "Nueva URL (Enter para guardar):", colors.white, colors.black)
          term.setCursorPos(2, 5); term.setTextColor(colors.white)
          local input = read(nil, nil, nil, ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080"))
          if input and #input > 0 then ctx.sys.setSetting("bridgeUrl", input) end
        end
      end
    end
  end,
}
