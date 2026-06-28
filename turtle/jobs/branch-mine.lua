-- turtle/jobs/branch-mine.lua  -- dig a main corridor with periodic side branches.
return {
  id = "branch-mine",
  label = "Branch mine",
  roles = { mineria = true },
  params = {
    { name = "depth",  label = "Largo del tunel", default = 24 },
    { name = "branch", label = "Largo de ramas",  default = 4 },
  },
  run = function(api)
    local depth = math.max(1, tonumber(api.params.depth) or 24)
    local branchLen = math.max(0, tonumber(api.params.branch) or 4)
    local SPACING = 3   -- a pair of branches every N corridor blocks

    -- one step of the 2-tall main corridor
    local function corridorStep()
      if not api.digMove("forward") then return false end
      api.dig("up")          -- head room; fails harmlessly under open sky
      return true
    end

    -- mine a branch to one side and come straight back, restoring corridor facing.
    -- Turn bookkeeping (turnRight=+1, turnLeft=-1, mod 4): after about-facing and
    -- walking back, one more turn toward the branch side returns us to the corridor.
    local function doBranch(side)
      if side == "left" then api.left() else api.right() end
      local got = 0
      for _ = 1, branchLen do
        if api.shouldCancel() then break end
        if not api.digMove("forward") then break end
        api.dig("up")
        got = got + 1
      end
      api.left(); api.left()                         -- about-face
      for _ = 1, got do api.forward() end            -- retrace exactly
      if side == "left" then api.left() else api.right() end
    end

    for i = 1, depth do
      if api.shouldCancel() then return false, ("cancelado en %d/%d"):format(i, depth) end
      if not corridorStep() then return false, ("bloqueada en %d/%d"):format(i, depth) end
      if branchLen > 0 and i % SPACING == 0 then
        doBranch("left"); doBranch("right")
      end
      if api.invFull() then return false, ("inventario lleno en %d"):format(i) end
      api.progress(math.floor(i / depth * 100), ("tunel %d/%d"):format(i, depth))
    end
    return true, ("tunel de %d completo"):format(depth)
  end,
}
