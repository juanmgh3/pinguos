-- dist/os/apps/about.lua  (also: the "hello world" template -- copy to start an app)
return {
  id = "about", name = "Acerca de", icon = "i", color = colors.lightBlue,
  desc = "Info de PinguOS",
  run = function(ctx)
    local close = ctx.ui.titleBar("Acerca de")
    ctx.ui.text(2, 3, "PinguOS " .. ctx.sys.version, colors.white, colors.black)
    local body = "Escritorio para CC: Tweaked. Las apps viven en /os/apps/. " ..
                 "Clic en [x] (o tecla Q) para volver al escritorio."
    local y = 5
    for _, line in ipairs(ctx.ui.wrap(body, ctx.width - 2)) do
      ctx.ui.text(2, y, line, colors.white, colors.black); y = y + 1
    end
    ctx.ui.statusBar("[x] o tecla Q para volver")
    while true do
      local ev = { os.pullEvent() }
      if ev[1] == "mouse_click" and ctx.ui.hit(close, ev[3], ev[4]) then return end
      if ev[1] == "key" and ev[2] == keys.q then return end
    end
  end,
}
