-- turtle/jobs/crop-loop.lua  -- tend a width x length field: harvest only ripe
-- crops, replant, and deposit into a chest behind the start. Loops until cancelled.
--
-- Uses a comb pattern (out-and-back per row, then shift right) instead of a
-- serpentine: it costs a few extra moves but always returns to the origin with the
-- same facing, which makes "go home and deposit" trivially correct.
return {
  id = "crop-loop",
  label = "Crop loop",
  roles = { granja = true },
  params = {
    { name = "width",  label = "Ancho (filas)",  default = 5 },
    { name = "length", label = "Largo de fila",  default = 5 },
  },
  run = function(api)
    local w = math.max(1, tonumber(api.params.width) or 5)
    local l = math.max(1, tonumber(api.params.length) or 5)

    -- Ripe = a crop block whose growth age has maxed out. Covers wheat, carrots and
    -- potatoes (age 0..7). Beetroot (0..3) won't trigger — documented limitation.
    local function ripe(d)
      if not d or not d.state then return false end
      local age = d.state.age
      return type(age) == "number" and age >= 7
    end

    local function tend()
      local _, d = api.inspect("down")
      if ripe(d) then
        api.dig("down")   -- harvest; turtle.dig collects the drops
        if api.selectItem("seed") or api.selectItem("carrot") or api.selectItem("potato") then
          api.place("down")
        end
      end
    end

    while true do
      if api.shouldCancel() then return false, "cosecha cancelada" end
      local done = 0
      for row = 1, w do
        for i = 1, l do
          if api.shouldCancel() then return false, "cosecha cancelada" end
          tend()
          if i < l then api.forward() end
        end
        api.left(); api.left()                  -- about-face
        for _ = 1, l - 1 do api.forward() end    -- walk back to row start
        api.left(); api.left()                   -- face forward again
        if row < w then api.right(); api.forward(); api.left() end  -- shift to next row
        done = done + 1
        api.progress(math.floor(done / w * 100), ("fila %d/%d"):format(done, w))
      end

      -- return to the origin column and deposit behind the start
      api.left()
      for _ = 1, w - 1 do api.forward() end
      api.right()
      api.left(); api.left()
      api.dropAll("forward")    -- into a chest behind the origin (or onto the ground)
      api.left(); api.left()

      sleep(5)   -- crops need time to regrow
    end
  end,
}
