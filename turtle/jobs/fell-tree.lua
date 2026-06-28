-- turtle/jobs/fell-tree.lua  -- fell the tree in front: climb the trunk, come back
-- down, and replant a sapling. Leaves are left to decay on their own.
return {
  id = "fell-tree",
  label = "Fell tree",
  roles = { tala = true },
  params = {},
  run = function(api)
    local function isLog(dir)
      local ok, d = api.inspect(dir)
      return ok and d and type(d.name) == "string" and d.name:find("log", 1, true) ~= nil
    end

    if not isLog("forward") and not isLog("up") then
      return false, "no hay arbol delante"
    end

    -- step into the trunk column if the log is in front
    if isLog("forward") then
      api.dig("forward"); api.forward()
    end

    -- climb while there is trunk above us
    local h = 0
    while isLog("up") do
      if api.shouldCancel() then break end
      if not api.digMove("up") then break end
      h = h + 1
      api.progress(50, ("subiendo %d"):format(h))
    end

    for _ = 1, h do api.down() end   -- back down to the base
    api.back()                       -- step out of the column

    if api.selectItem("sapling") then api.place("forward") end
    api.progress(100, "arbol talado")
    return true, ("arbol de altura %d talado"):format(h + 1)
  end,
}
