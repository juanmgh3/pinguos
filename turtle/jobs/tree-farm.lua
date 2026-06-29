-- turtle/jobs/tree-farm.lua  -- patrol a walkway; tend the planting row to the
-- RIGHT of each step (fell grown trees via api.chopTree, replant saplings). Runs
-- until cancelled. For sweeping a whole 2D patch instead of one row, use `lumber`.
--
-- Layout: the turtle stands on a clear walkway `length` blocks long; the cells to
-- its right are the planting row, kept separate so it never walks into a tree.
return {
  id = "tree-farm",
  label = "Tree farm",
  roles = { tala = true },
  params = {
    { name = "length", label = "Largo de la fila", default = 6 },
  },
  run = function(api)
    local length = math.max(1, tonumber(api.params.length) or 6)

    -- We are facing the planting cell (turned right). Fell a tree if present,
    -- otherwise plant a sapling on bare ground.
    local function tendCell()
      if api.isLog("forward") then
        api.chopTree()
      elseif not api.detect("forward") and api.selectItem("sapling") then
        api.place("forward")
      end
    end

    while true do
      if api.shouldCancel() then return false, "patrulla cancelada" end
      for i = 1, length do
        if api.shouldCancel() then return false, "patrulla cancelada" end
        api.right(); tendCell(); api.left()        -- tend the cell on our right
        api.progress(math.floor(i / length * 100), ("fila %d/%d"):format(i, length))
        if i < length then api.forward() end       -- advance along the walkway
      end
      api.left(); api.left()
      for _ = 1, length - 1 do api.forward() end
      api.left(); api.left()
      sleep(3)   -- trees need time to grow; don't busy-spin the row
    end
  end,
}
