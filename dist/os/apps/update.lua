-- dist/os/apps/update.lua
return {
  id = "update", name = "Update", icon = "@", color = colors.green,
  desc = "Actualizar desde el bridge",
  run = function(ctx)
    ctx.ui.clear(); ctx.ui.titleBar("Update")
    local base = ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080")
    ctx.ui.text(2, 3, "Bajando de " .. base, colors.white, colors.black)
    local h = http.get(base .. "/manifest")
    if not h then
      ctx.ui.text(2, 5, "No hay bridge. Esta corriendo?", colors.red, colors.black)
      ctx.ui.text(2, 7, "Pulsa una tecla", colors.white, colors.black)
      os.pullEvent("key"); return
    end
    local m = textutils.unserialiseJSON(h.readAll()); h.close()
    for _, f in ipairs(m.files) do
      local fh = http.get(base .. "/fs" .. f.path)
      if fh then
        local data = fh.readAll(); fh.close()
        local d = f.path:match("^(.*)/[^/]+$")
        if d and d ~= "" and not fs.exists(d) then fs.makeDir(d) end
        local tmp = f.path .. ".tmp"
        local out = fs.open(tmp, "w"); out.write(data); out.close()
        if fs.exists(f.path) then fs.delete(f.path) end
        fs.move(tmp, f.path)
        ctx.log("updated " .. f.path)
      end
    end
    ctx.ui.text(2, 5, "Actualizado a " .. (m.version or "?") .. ". Reiniciando...",
                colors.lime, colors.black)
    sleep(1); os.reboot()
  end,
}
