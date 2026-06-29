-- turtle/lib/api.lua  -- the helper handed to every job. Wraps turtle.* with the
-- "common sense" a job shouldn't have to repeat: fuel-safe moves, dig-through-
-- gravel, inventory queries, progress reporting, cancellation. CC-bound: this can
-- only be `luac -p` checked, never unit-tested (every call hits the turtle API).
--
-- Returned as a constructor. The agent owns the glue (rednet identity, the cancel
-- flag, telemetry setters) and passes it in as `ctx`.
return function(ctx)
  local api = {}
  api.params = ctx.params or {}
  api.nav = ctx.nav            -- pure navigation math, for the goto job

  ---- fuel -------------------------------------------------------------------
  function api.fuel() return turtle.getFuelLevel() end

  -- Ensure we can move. Try to burn anything flammable in the inventory if empty.
  function api.refuel()
    local lvl = turtle.getFuelLevel()
    if lvl == "unlimited" or (type(lvl) == "number" and lvl > 0) then return true end
    for s = 1, 16 do
      turtle.select(s)
      if turtle.refuel(1) then turtle.select(1); return true end
    end
    turtle.select(1)
    ctx.setStatus("nofuel")
    return false
  end

  ---- moves (fuel-safe) ------------------------------------------------------
  local function guardedMove(mv)
    if not api.refuel() then return false end
    return mv()
  end
  function api.forward() return guardedMove(turtle.forward) end
  function api.back()    return guardedMove(turtle.back) end
  function api.up()      return guardedMove(turtle.up) end
  function api.down()    return guardedMove(turtle.down) end
  function api.left()  turtle.turnLeft();  return true end
  function api.right() turtle.turnRight(); return true end

  -- Apply a rotation from nav.turns(): 0 none, 1 right, -1 left, 2 about-face.
  function api.turn(n)
    if n == 1 then turtle.turnRight()
    elseif n == -1 then turtle.turnLeft()
    elseif n == 2 then turtle.turnRight(); turtle.turnRight() end
  end

  ---- dig + move (handles falling gravel/sand; gives up on bedrock) ----------
  local DIG = { forward = turtle.dig,    up = turtle.digUp,    down = turtle.digDown }
  local DET = { forward = turtle.detect, up = turtle.detectUp, down = turtle.detectDown }
  local MOV = { forward = api.forward,   up = api.up,          down = api.down }

  function api.digMove(dir)
    dir = dir or "forward"
    local dig, det, mov = DIG[dir], DET[dir], MOV[dir]
    local guard = 0
    while det() do
      if not dig() then return false end  -- unbreakable (bedrock) or wrong tool
      guard = guard + 1
      if guard > 128 then ctx.setStatus("blocked"); return false end
      sleep(0)                            -- let gravel/sand fall, then re-check
    end
    return mov()
  end

  function api.dig(dir) return (DIG[dir or "forward"])() end

  ---- inspect / detect -------------------------------------------------------
  local INS = { forward = turtle.inspect, up = turtle.inspectUp, down = turtle.inspectDown }
  function api.inspect(dir) return (INS[dir or "forward"])() end  -- ok, data
  function api.detect(dir)  return (DET[dir or "forward"])() end

  ---- inventory --------------------------------------------------------------
  function api.invFull()
    for s = 1, 16 do if turtle.getItemCount(s) == 0 then return false end end
    return true
  end
  function api.invPct()
    local used = 0
    for s = 1, 16 do if turtle.getItemCount(s) > 0 then used = used + 1 end end
    return math.floor(used / 16 * 100)
  end
  -- Select the first slot whose item name contains `match` (e.g. "sapling","seed").
  function api.selectItem(match)
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name:find(match, 1, true) then turtle.select(s); return true end
    end
    return false
  end
  function api.dropAll(dir)
    local drop = ({ forward = turtle.drop, up = turtle.dropUp, down = turtle.dropDown })[dir or "forward"]
    for s = 1, 16 do
      if turtle.getItemCount(s) > 0 then turtle.select(s); drop() end
    end
    turtle.select(1)
  end

  ---- placing ----------------------------------------------------------------
  function api.place(dir)
    return (({ forward = turtle.place, up = turtle.placeUp, down = turtle.placeDown })[dir or "forward"])()
  end

  ---- perception & trees (reusable "smarts") --------------------------------
  -- A turtle only senses the 3 blocks it touches (front/up/down) -- there is no
  -- area scanner on this setup. "Searching" therefore means sweeping an area and
  -- reacting to what turns up adjacent; these helpers make that cheap.
  function api.isLog(dir)
    local ok, d = api.inspect(dir)
    if not (ok and d) then return false end
    return ctx.blocks.isLog(d.name)
  end

  function api.isOre(dir)
    local ok, d = api.inspect(dir)
    if not (ok and d) then return false end
    return ctx.blocks.isOre(d.name)
  end

  -- Fell the tree whose trunk is directly in front: step in, climb it, come back
  -- down, step out, replant a sapling if we carry one. Returns the trunk height
  -- (0 if there was no log in front). Shared by fell-tree, tree-farm and lumber.
  function api.chopTree()
    if not api.isLog("forward") then return 0 end
    api.dig("forward"); api.forward()
    local h = 0
    while api.isLog("up") do
      if not api.digMove("up") then break end
      h = h + 1
    end
    for _ = 1, h do api.down() end
    api.back()
    if api.selectItem("sapling") then api.place("forward") end
    return h + 1
  end

  ---- control glue (owned by the agent) -------------------------------------
  function api.shouldCancel() return ctx.shouldCancel() end

  -- Report progress. Local telemetry updates every call (cheap), but the rednet
  -- broadcast is THROTTLED to ~2/s. Jobs call this every block; several working
  -- turtles broadcasting every step floods the fleet computer's event queue (a real
  -- limit inside CC) and freezes a pocket. The completion (100%) always goes out.
  local lastBroadcast = 0
  function api.progress(pct, info)
    ctx.setProg(pct, info)
    local now = os.clock()
    if (pct or 0) < 100 and (now - lastBroadcast) < 0.5 then return end
    lastBroadcast = now
    rednet.broadcast({
      t = "progress", name = ctx.name, job = ctx.job,
      pct = pct, info = info, fuel = turtle.getFuelLevel(), pos = ctx.pos(),
    }, ctx.protocol)
    if ctx.redraw then ctx.redraw() end
  end

  return api
end
