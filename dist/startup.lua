-- dist/startup.lua
package.path = "/os/?.lua;" .. package.path
local ok, err = pcall(function()
  require("kernel").run()
end)
if not ok then
  term.setBackgroundColor(colors.blue); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  print("PinguOS panic:")
  print(tostring(err))
  print("")
  print("Press T for the shell.")
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.t then
      term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1); return
    end
  end
end
