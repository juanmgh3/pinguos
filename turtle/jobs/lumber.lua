-- turtle/jobs/lumber.lua  -- autonomous AREA lumberjack: sweep a width x length
-- patch and fell EVERY tree in (and bordering) it, replanting, in a loop.
--
-- HONEST LIMIT: a turtle here has no area scanner (no Advanced Peripherals), so it
-- can only sense the blocks it touches. "Detecting nearby trees" therefore means
-- sweeping the patch and, AT EVERY CELL, turning to look in all 4 directions and
-- felling whatever log is adjacent. That covers the whole patch plus its border --
-- the closest thing to "see trees nearby and go chop them" the hardware allows.
-- Plant the first saplings; after that it replants each tree it fells. Flat ground.
return {
  id = "lumber",
  label = "Lenador (area)",
  roles = { tala = true },
  params = {
    { name = "width",  label = "Ancho (filas)", default = 5 },
    { name = "length", label = "Largo de fila", default = 5 },
  },
  run = function(api)
    local w = math.max(1, tonumber(api.params.width) or 5)
    local l = math.max(1, tonumber(api.params.length) or 5)

    -- Advance one cell, forcing through anything in the way (incl. non-solid
    -- saplings/grass that turtle.detect can't see), so the sweep never jams.
    local function step()
      if api.forward() then return true end
      api.dig("forward")
      if api.forward() then return true end
      return api.digMove("forward")   -- fallback: handle falling gravel/sand
    end

    -- Look in all 4 directions and fell any adjacent tree. chopTree steps in and
    -- back out, so it ends facing the same way; 4 right-turns restore our heading.
    local function reapAround()
      for _ = 1, 4 do
        if api.isLog("forward") then api.chopTree() end
        api.right()
      end
    end

    while true do
      if api.shouldCancel() then return false, "lenador cancelado" end
      local cells, total = 0, w * l
      for row = 1, w do
        for i = 1, l do
          if api.shouldCancel() then return false, "lenador cancelado" end
          reapAround()
          cells = cells + 1
          api.progress(math.floor(cells / total * 100), ("barriendo %d/%d"):format(cells, total))
          if i < l then step() end
        end
        api.left(); api.left()                  -- about-face
        for _ = 1, l - 1 do step() end           -- walk back along the row
        api.left(); api.left()                   -- face forward again
        if row < w then api.right(); step(); api.left() end  -- shift to next row
      end
      api.left()                                 -- return to the origin column
      for _ = 1, w - 1 do step() end
      api.right()
      sleep(8)   -- let replanted saplings grow before sweeping again
    end
  end,
}
