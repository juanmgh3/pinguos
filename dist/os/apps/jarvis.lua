-- dist/os/apps/jarvis.lua -- chat UI for the JARVIS agent. Loads the jarvis modules
-- via loadfile (require is unavailable in apps) and drives agent.run.
return {
  id = "jarvis", name = "JARVIS", icon = "J", color = colors.cyan,
  desc = "Asistente de la base",
  run = function(ctx)
    local ui = ctx.ui
    local function load(n) return assert(loadfile("/os/jarvis/" .. n .. ".lua"))() end
    local protocol, claudecc, tools, agent = load("protocol"), load("claudecc"), load("tools"), load("agent")
    agent.init(protocol, claudecc, tools)

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
    local function emit(kind, text)
      text = sanitize(tostring(text or ""))
      if kind == "tool" then colour(colors.lightGray); print("  [tool: " .. text .. "]")
      elseif kind == "result" then colour(colors.gray); print("  [result: " .. text:sub(1, 2 * W) .. "]")
      elseif kind == "answer" then colour(colors.cyan); term.write("jarvis > "); colour(colors.white); print(text)
      elseif kind == "error" then colour(colors.red); print("error: " .. text) end
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

    local ok, err = pcall(function()
      if not claudecc.available() then
        colour(colors.red); print("ClaudeCraft no detectado.")
        print("Configura /claudecraft y reabre. [x] para salir.")
        while true do
          local ev, a, b, c = os.pullEvent()
          if ev == "mouse_click" and ui.hit(close, b, c) then return end
          if ev == "key" and a == keys.q then return end
        end
      end
      print("JARVIS listo. Escribe una orden, o [x] para salir.")
      while true do
        local msg = inputLine()
        if msg == nil then return end
        msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "exit" or msg == "quit" then return
        elseif #msg > 0 then agent.run(ctx, worldMd, msg, emit) end
      end
    end)
    restore()
    if not ok then error(err, 0) end
  end,
}
