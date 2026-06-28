-- turtle/jobs/dig-down.lua  -- dig straight down N blocks (or to bedrock), then
-- climb back to the surface so the turtle never strands itself at the bottom.
return {
  id = "dig-down",
  label = "Dig down",
  roles = { mineria = true },
  params = {
    { name = "depth", label = "Cuantos bloques", default = 16 },
  },
  run = function(api)
    local depth = math.max(1, tonumber(api.params.depth) or 16)
    local went = 0
    for i = 1, depth do
      if api.shouldCancel() then break end
      if not api.digMove("down") then break end   -- bedrock / unbreakable stops us
      went = went + 1
      api.progress(math.floor(i / depth * 100), ("bajando %d/%d"):format(i, depth))
    end
    -- always climb back up, cancel or not, to return to the surface.
    for _ = 1, went do
      if not api.up() then api.digMove("up") end
    end
    return true, ("pozo de %d (de vuelta arriba)"):format(went)
  end,
}
