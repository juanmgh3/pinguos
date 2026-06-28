-- turtle/jobs/tree-farm.lua  -- patrol a walkway; tend the planting row to the
-- RIGHT of each step (fell grown trees, replant saplings). Runs until cancelled.
--
-- Layout: the turtle stands on a clear walkway `length` blocks long. The cells to
-- its right are the planting row. This keeps the walkway and the trees separate so
-- the turtle never has to walk through a growing tree.
return {
  id = "tree-farm",
  label = "Tree farm",
  roles = { tala = true },
  params = {
    { name = "length", label = "Largo de la fila", default = 6 },
  },
  run = function(api)
    local length = math.max(1, tonumber(api.params.length) or 6)

    local function isLog(dir)
      local ok, d = api.inspect(dir)
      return ok and d and type(d.name) == "string" and d.name:find("log", 1, true) ~= nil
    end

    -- We are facing the planting cell (turned right). Fell a tree if present,
    -- otherwise plant a sapling on bare ground.
    local function tendCell()
      if not isLog("forward") then
        if not api.detect("forward") and api.selectItem("sapling") then api.place("forward") end
        return
      end
      api.dig("forward"); api.forward()
      local h = 0
      while isLog("up") do
        if not api.digMove("up") then break end
        h = h + 1
      end
      for _ = 1, h do api.down() end
      api.back()
      if api.selectItem("sapling") then api.place("forward") end
    end

    while true do
      if api.shouldCancel() then return false, "patrulla cancelada" end
      for i = 1, length do
        if api.shouldCancel() then return false, "patrulla cancelada" end
        api.right(); tendCell(); api.left()        -- tend the cell on our right
        api.progress(math.floor(i / length * 100), ("fila %d/%d"):format(i, length))
        if i < length then api.forward() end       -- advance along the walkway
      end
      -- walk back to the start of the walkway, ready for the next pass
      api.left(); api.left()
      for _ = 1, length - 1 do api.forward() end
      api.left(); api.left()
      sleep(3)   -- trees need time to grow; don't busy-spin the row
    end
  end,
}
