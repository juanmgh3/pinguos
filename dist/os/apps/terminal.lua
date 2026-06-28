-- dist/os/apps/terminal.lua
return {
  id = "terminal", name = "Terminal", icon = ">", color = colors.gray,
  desc = "Shell de CraftOS",
  run = function(ctx)
    ctx.ui.clear()
    term.setTextColor(colors.white)
    print("CraftOS shell. Escribe 'exit' para volver a PinguOS.")
    shell.run("shell")
  end,
}
