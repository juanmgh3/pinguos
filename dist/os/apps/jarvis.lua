-- dist/os/apps/jarvis.lua -- JARVIS: thin launcher for ClaudeCraft's native `claude` client.
-- In channel mode the client owns the full agentic loop: it sends messages AND executes the
-- brain's tool calls (claude_tool_exec -> run -> sendToolResult). Reimplementing that in Lua
-- is redundant and drifts on mod updates, so JARVIS hands the terminal to the rom `claude`
-- program and returns to the PinguOS desktop on exit. Base knowledge lives in
-- /data/jarvis/world.md and the fleet helper in /os/jarvis/fleet_status.lua (the brain can
-- read_file / run_command them). See specs/pinguos/jarvis-core.md.
return {
  id = "jarvis", name = "JARVIS", icon = "J", color = colors.cyan,
  desc = "Operador de la base (ClaudeCraft)",
  run = function(ctx)
    local ui = ctx.ui

    local function notice(msg1, msg2)
      ui.clear(); ui.titleBar("JARVIS")
      term.setTextColor(colors.red); term.setCursorPos(2, 3); print(msg1)
      term.setTextColor(colors.white)
      if msg2 then term.setCursorPos(2, 5); print(msg2) end
      term.setCursorPos(2, 7); print("Pulsa una tecla para volver.")
      os.pullEvent("key")
    end

    if type(_G.claude) ~= "table" then
      notice("ClaudeCraft no detectado.",
             "Ejecuta 'claude' una vez, elige Channel mode, y reabre JARVIS.")
      return
    end
    local sh = _G.shell
    if not sh then
      notice("shell no disponible en este contexto.")
      return
    end

    -- Hand the whole terminal to ClaudeCraft's native client. It draws its own UI and
    -- returns when you type exit/quit; the kernel then clears + redraws the desktop.
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)
    sh.run("claude")
    term.setCursorBlink(false)
  end,
}
