-- dist/os/apps/settings.lua
return {
  id = "settings", name = "Ajustes", icon = "*", color = colors.orange,
  desc = "Tema y conexion",
  run = function(ctx)
    local ui = ctx.ui
    local accents = { colors.cyan, colors.lime, colors.orange, colors.magenta, colors.red }
    local names   = { "cyan", "lime", "orange", "magenta", "red" }
    while true do
      ui.clear()
      local close = ui.titleBar("Ajustes")
      ui.text(2, 3, "Color de acento:", colors.white, colors.black)
      local btns = {}
      for i = 1, #accents do
        local x = 2 + (i - 1) * 9
        ui.fill(x, 5, 8, 1, accents[i])
        ui.text(x, 5, " " .. names[i], colors.black, accents[i])
        btns[i] = { x = x, y = 5, w = 8, h = 1 }
      end
      ui.text(2, 8, "Bridge URL:", colors.white, colors.black)
      ui.text(2, 9, ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080"),
              colors.lightGray, colors.black)
      local editBtn = ui.button(2, 11, "Editar URL")
      ui.statusBar("clic en un color o en Editar URL")
      local ev = { os.pullEvent() }
      if ev[1] == "mouse_click" then
        if ui.hit(close, ev[3], ev[4]) then return end
        for i = 1, #btns do
          if ui.hit(btns[i], ev[3], ev[4]) then
            ui.setTheme({ accent = accents[i] })
            ctx.sys.setSetting("accent", accents[i])
          end
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
