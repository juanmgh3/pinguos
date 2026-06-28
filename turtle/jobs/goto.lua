-- turtle/jobs/goto.lua  -- best-effort GPS navigation to (x,y,z). A turtle has no
-- compass, so we infer our heading by moving one block and comparing GPS fixes,
-- then resolve each axis in turn. Obstacle handling is deliberately simple (dig
-- through, or climb over) -- real pathfinding is out of scope (see the spec).
return {
  id = "goto",
  label = "Ir a (GPS)",
  roles = { any = true },
  params = {
    { name = "x", label = "X destino", default = 0 },
    { name = "y", label = "Y destino", default = 64 },
    { name = "z", label = "Z destino", default = 0 },
  },
  run = function(api)
    local nav = api.nav
    local tx, ty, tz = tonumber(api.params.x), tonumber(api.params.y), tonumber(api.params.z)
    if not (tx and ty and tz) then return false, "coords invalidas" end

    local function relocate()
      local x, y, z = gps.locate(2)
      if x then return { x = x, y = y, z = z } end
      return nil
    end

    local cur = relocate()
    if not cur then return false, "sin GPS (faltan balizas)" end

    local function resolveY()
      local guard = 0
      while cur.y ~= ty do
        if api.shouldCancel() then return false end
        if cur.y < ty then
          if not api.up() then api.digMove("up") end
        else
          if not api.down() then api.digMove("down") end
        end
        cur = relocate() or cur
        guard = guard + 1
        if guard > 256 then return false end
        api.progress(30, ("Y %d -> %d"):format(cur.y, ty))
      end
      return true
    end

    -- infer heading by moving one block along whatever horizontal axis is free
    local heading = nil
    local function calibrate()
      for _ = 1, 4 do
        local before = relocate()
        if not before then return false end
        if api.digMove("forward") then
          local after = relocate()
          if after then
            local h = nav.headingFromMove(before, after)
            if h then heading = h; cur = after; return true end
          end
          cur = after or cur
          return false
        end
        api.right()   -- blocked this way; face a new direction and retry
      end
      return false
    end

    local function walkAxis(axis)
      cur = relocate() or cur
      local function rem() if axis == "x" then return tx - cur.x else return tz - cur.z end end
      local guard = 0
      while rem() ~= 0 do
        if api.shouldCancel() then return false end
        local want = nav.headingForAxis(axis, rem())
        api.turn(nav.turns(heading, want)); heading = want
        if not api.digMove("forward") then
          api.digMove("up")   -- blocked: climb over, Y gets corrected at the end
        end
        cur = relocate() or cur
        guard = guard + 1
        if guard > 512 then return false end
        api.progress(66, ("%s faltan %d"):format(axis, rem()))
      end
      return true
    end

    if not resolveY() then return false, "no pude ajustar Y" end
    if not calibrate() then return false, "no pude orientarme (encerrada?)" end
    walkAxis("x")
    walkAxis("z")
    resolveY()   -- climbing over obstacles may have changed Y
    cur = relocate() or cur
    api.progress(100, "llegada")
    return true, ("en %d,%d,%d"):format(cur.x, cur.y, cur.z)
  end,
}
