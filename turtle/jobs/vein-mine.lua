-- turtle/jobs/vein-mine.lua  -- dig a corridor and, at every step, chase any ore
-- vein found in the 6 surrounding faces, extracting the WHOLE vein and returning
-- to the corridor on its own.
--
-- The vein chase is a recursive flood-fill that UNDOES ITSELF: for each ore block
-- it enters, it recurses, then reverses that exact move (entered up -> come down,
-- entered forward -> go back). The path it opened is all mined-out air, so the
-- return is always free and lands back at the start -- no GPS, no coordinate
-- tracking. Mining turns ore into air, so no block is ever visited twice.
return {
  id = "vein-mine",
  label = "Vetas (auto)",
  roles = { mineria = true },
  params = {
    { name = "depth", label = "Largo del tunel", default = 24 },
  },
  run = function(api)
    local depth = math.max(1, tonumber(api.params.depth) or 24)
    local MAXDEPTH = 96   -- recursion cap; huge connected ore bodies stop here

    -- Stand on a just-mined ore block; pull the rest of the vein, then unwind.
    local function mineVein(level)
      if level > MAXDEPTH or api.shouldCancel() then return end
      if api.isOre("up") then
        api.digMove("up"); mineVein(level + 1)
        if not api.down() then api.digMove("down") end       -- gravel may have fallen
      end
      if api.isOre("down") then
        api.digMove("down"); mineVein(level + 1)
        if not api.up() then api.digMove("up") end
      end
      for _ = 1, 4 do                                          -- the 4 horizontal faces
        if api.isOre("forward") then
          api.digMove("forward"); mineVein(level + 1); api.back()
        end
        api.right()                                            -- 4 turns => facing restored
      end
    end

    for i = 1, depth do
      if api.shouldCancel() then return false, ("cancelado en %d/%d"):format(i, depth) end
      if not api.digMove("forward") then return false, ("bloqueada en %d/%d"):format(i, depth) end
      mineVein(0)                                              -- scan + chase from this cell
      if api.invFull() then return false, ("inventario lleno en %d"):format(i) end
      api.progress(math.floor(i / depth * 100), ("tunel+vetas %d/%d"):format(i, depth))
    end
    return true, ("tunel de %d con vetas extraidas"):format(depth)
  end,
}
