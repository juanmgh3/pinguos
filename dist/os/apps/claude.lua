-- dist/os/apps/claude.lua
return {
  id = "claude", name = "Claude", icon = "C", color = colors.cyan,
  desc = "Chat con Claude",
  run = function(ctx)
    local ui = ctx.ui
    local url = ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080")
    local token = ctx.sys.getSetting("bridgeToken", "")
    local W, H = term.getSize()
    ui.clear()
    local close = ui.titleBar("Claude")           -- fixed on row 1 of the main term
    local win = window.create(term.current(), 1, 2, W, H - 1)
    local old = term.redirect(win)                -- transcript scrolls inside the window
    local function restore() term.redirect(old) end

    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)

    local function colour(c) if term.isColour() then term.setTextColor(c) end end
    local function sanitize(s) return (s:gsub("\r", ""):gsub("[^\n\t -~]", "")) end

    local function say(body)
      body = sanitize(body)
      colour(colors.cyan); term.write("claude > "); colour(colors.white)
      local lines = ui.wrap(body, W)
      if #lines <= 1 and (9 + #(lines[1] or "")) <= W then
        print(lines[1] or "")
      else
        print()
        for _, ln in ipairs(lines) do print(ln) end
      end
    end

    -- Custom input: types text, but also returns nil if the [x] is clicked.
    local function inputLine()
      print()
      colour(colors.yellow); term.write("you > "); colour(colors.white)
      local px, py = term.getCursorPos()
      local buf = ""
      term.setCursorBlink(true)
      while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "char" then
          buf = buf .. a; term.write(a)
        elseif ev == "key" then
          if a == keys.enter then
            term.setCursorBlink(false); print(); return buf
          elseif a == keys.backspace and #buf > 0 then
            buf = buf:sub(1, #buf - 1)
            term.setCursorPos(px, py); term.write(buf .. " "); term.setCursorPos(px + #buf, py)
          end
        elseif ev == "mouse_click" and ui.hit(close, b, c) then
          term.setCursorBlink(false); return nil
        end
      end
    end

    local function request(bodyTable)
      http.request({
        url = url, body = textutils.serialiseJSON(bodyTable),
        headers = {
          ["Content-Type"] = "application/json",
          ["X-Bridge-Token"] = token,
        },
        timeout = 120,
      })
      local frames, fi = "|/-\\", 1
      term.write("claude esta pensando... ")
      local hx, hy = term.getCursorPos()
      local tid = os.startTimer(0.15)
      while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "timer" and a == tid then
          term.setCursorPos(hx, hy); term.write(frames:sub(fi, fi))
          fi = fi % #frames + 1; tid = os.startTimer(0.15)
        elseif ev == "http_success" then
          local raw = b.readAll(); b.close()
          term.setCursorPos(1, hy); term.clearLine(); return raw, nil
        elseif ev == "http_failure" then
          local raw = nil; if c then raw = c.readAll(); c.close() end
          term.setCursorPos(1, hy); term.clearLine(); return raw, (b or "fallo")
        end
      end
    end

    local function handle(raw, err)
      if err and not raw then
        printError("error: " .. tostring(err))
        printError("(bridge en " .. url .. " ?)")
        if ctx.sound then ctx.sound.error() end
        return
      end
      local ok, data = pcall(textutils.unserialiseJSON, raw)
      if ok and data and data.text then say(data.text)
      elseif ok and data and data.error then printError("bridge: " .. tostring(data.error))
      else say(raw or "(sin respuesta)") end
    end

    local ok, err = pcall(function()
      print("Claude listo. Escribe, o pulsa [x]. 'reset' olvida.")
      while true do
        local msg = inputLine()
        if msg == nil then return end
        msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "exit" or msg == "quit" then return
        elseif msg == "reset" then handle(request({ reset = true }))
        elseif #msg > 0 then handle(request({ prompt = msg })) end
      end
    end)
    restore()
    if not ok then error(err, 0) end
  end,
}
