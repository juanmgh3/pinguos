-- dist/os/apps/claude.lua
return {
  id = "claude", name = "Claude", icon = "C", color = colors.cyan,
  desc = "Chat con Claude",
  run = function(ctx)
    local ui = ctx.ui
    local url = ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080")
    local w = term.getSize()
    ui.clear(); ui.titleBar("Claude")
    term.setCursorPos(1, 3)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)

    local function colour(c) if term.isColour() then term.setTextColor(c) end end
    local function sanitize(s) return (s:gsub("\r", ""):gsub("[^\n\t -~]", "")) end

    local function say(body)
      body = sanitize(body)
      colour(colors.cyan); term.write("claude > "); colour(colors.white)
      local lines = ui.wrap(body, w)
      if #lines <= 1 and (9 + #(lines[1] or "")) <= w then
        print(lines[1] or "")
      else
        print()
        for _, ln in ipairs(lines) do print(ln) end
      end
    end

    local function request(bodyTable)
      http.request({
        url = url, body = textutils.serialiseJSON(bodyTable),
        headers = { ["Content-Type"] = "application/json" }, timeout = 120,
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
        elseif ev == "http_success" then        -- a=url, b=handle
          local raw = b.readAll(); b.close()
          term.setCursorPos(1, hy); term.clearLine()
          return raw, nil
        elseif ev == "http_failure" then         -- a=url, b=errmsg, c=handle?
          local raw = nil; if c then raw = c.readAll(); c.close() end
          term.setCursorPos(1, hy); term.clearLine()
          return raw, (b or "request failed")
        end
      end
    end

    local function handle(raw, err)
      if err and not raw then
        printError("error: " .. tostring(err))
        printError("(bridge encendido en " .. url .. " ?)")
        return
      end
      local ok, data = pcall(textutils.unserialiseJSON, raw)
      if ok and data and data.text then say(data.text)
      elseif ok and data and data.error then printError("bridge: " .. tostring(data.error))
      else say(raw or "(sin respuesta)") end
    end

    print("Claude listo. 'exit' vuelve al escritorio, 'reset' olvida la charla.")
    while true do
      print()
      colour(colors.yellow); term.write("you > "); colour(colors.white)
      local msg = read()
      if msg == nil then return end
      msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
      if msg == "exit" or msg == "quit" then return
      elseif msg == "reset" then handle(request({ reset = true }))
      elseif #msg > 0 then handle(request({ prompt = msg })) end
    end
  end,
}
