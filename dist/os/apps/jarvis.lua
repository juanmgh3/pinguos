-- dist/os/apps/jarvis.lua -- thin chat UI over the ClaudeCraft brain. Loads claudecc via
-- loadfile (require is unavailable in apps) and relays messages; the brain does the work.
-- Reuses the claude.lua app pattern (titleBar -> window -> redirect -> input loop).
return {
  id = "jarvis", name = "JARVIS", icon = "J", color = colors.cyan,
  desc = "Operador de la base",
  run = function(ctx)
    local ui = ctx.ui
    local claudecc = assert(loadfile("/os/jarvis/claudecc.lua"))()

    local worldMd = ""
    if fs.exists("/data/jarvis/world.md") then
      local fh = fs.open("/data/jarvis/world.md", "r"); worldMd = fh.readAll(); fh.close()
    end

    local W, H = term.getSize()
    ui.clear()
    local close = ui.titleBar("JARVIS")
    local win = window.create(term.current(), 1, 2, W, H - 1)
    local old = term.redirect(win)
    local function restore() term.redirect(old) end
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)

    local function colour(c) if term.isColour() then term.setTextColor(c) end end
    local function sanitize(s) return (s:gsub("\r", ""):gsub("[^\n\t -~]", "")) end
    local function say(who, body, c)
      colour(c); term.write(who .. " > "); colour(colors.white)
      local lines = ui.wrap(sanitize(body), W)
      if #lines <= 1 and (#who + 3 + #(lines[1] or "")) <= W then print(lines[1] or "")
      else print(); for _, ln in ipairs(lines) do print(ln) end end
    end

    -- input line: types text; returns nil if [x] is clicked (mirrors claude.lua)
    local function inputLine()
      print()
      colour(colors.yellow); term.write("you > "); colour(colors.white)
      local px, py = term.getCursorPos()
      local buf = ""
      term.setCursorBlink(true)
      while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "char" then buf = buf .. a; term.write(a)
        elseif ev == "key" then
          if a == keys.enter then term.setCursorBlink(false); print(); return buf
          elseif a == keys.backspace and #buf > 0 then
            buf = buf:sub(1, #buf - 1)
            term.setCursorPos(px, py); term.write(buf .. " "); term.setCursorPos(px + #buf, py)
          end
        elseif ev == "mouse_click" and ui.hit(close, b, c) then
          term.setCursorBlink(false); return nil
        end
      end
    end

    -- print the raw reply event once, to pin the exact event name/field in-game.
    local pinned = false
    local function onEvent(name, ev)
      if pinned then return end
      pinned = true
      colour(colors.gray)
      print(("  [reply event: %s | f2=%s]"):format(name, tostring(ev[2]):sub(1, 28)))
    end

    local ok, err = pcall(function()
      if not claudecc.available() then
        colour(colors.red); print("ClaudeCraft no detectado.")
        print("Configura /claudecraft y reabre. [x] para salir.")
        while true do
          local e, a, b, c = os.pullEvent()
          if e == "mouse_click" and ui.hit(close, b, c) then return end
          if e == "key" and a == keys.q then return end
        end
      end

      colour(colors.lightGray); print("Conectando con el cerebro...")
      local session = claudecc.open()
      if not session.ready then
        colour(colors.orange)
        print("Canal no listo (isChannelReady=false). Confirma el 'trust' en la")
        print("ventana de Claude Code; si ya lo hiciste, prueba a preguntar igual.")
      end
      colour(colors.cyan); print("JARVIS listo. Escribe una orden, o [x] para salir.")

      local seeded = false
      while true do
        local msg = inputLine()
        if msg == nil then return end
        msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "exit" or msg == "quit" then return
        elseif #msg > 0 then
          local payload = msg
          if not seeded and #worldMd > 0 then
            payload = worldMd .. "\n\n---\nUsuario: " .. msg
            seeded = true
          end
          colour(colors.gray); print("pensando...")
          local reply, evname = claudecc.send(session, payload, onEvent)
          if reply then say("jarvis", reply, colors.cyan)
          else say("jarvis", "(sin respuesta: " .. tostring(evname) .. ")", colors.red) end
        end
      end
    end)
    restore()
    if not ok then error(err, 0) end
  end,
}
