-- dist/os/focus.lua  -- pure keyboard-focus navigation math (no CC globals).
-- Phase 1 uses center + spatial for the desktop icon grid. Unit-tested on Lua 5.4
-- (dist/tests/test_focus.lua); loads clean in both CC 5.1 and local 5.4.
local focus = {}

-- Integer centre cell of a region {x,y,w,h}.
function focus.center(r)
  return r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2)
end

-- Nearest focusable in a spatial direction.
--   rects   : list of {x,y,w,h}
--   current : 1-based index of the focused rect
--   dir     : "up" | "down" | "left" | "right"
-- Returns the new index (current if nothing lies that way; 0 if empty;
-- 1 if current is out of range). A candidate counts as "in dir" when its centre
-- is on that side AND the move is more along that axis than across it; ties break
-- on squared centre-distance (closest wins).
function focus.spatial(rects, current, dir)
  if #rects == 0 then return 0 end
  if current < 1 or current > #rects then return 1 end
  local cx, cy = focus.center(rects[current])
  local best, bestScore = current, nil
  for i, r in ipairs(rects) do
    if i ~= current then
      local ix, iy = focus.center(r)
      local dx, dy = ix - cx, iy - cy
      local aligned =
           (dir == "right" and dx > 0 and math.abs(dx) >= math.abs(dy))
        or (dir == "left"  and dx < 0 and math.abs(dx) >= math.abs(dy))
        or (dir == "down"  and dy > 0 and math.abs(dy) >= math.abs(dx))
        or (dir == "up"    and dy < 0 and math.abs(dy) >= math.abs(dx))
      if aligned then
        local score = dx * dx + dy * dy
        if not bestScore or score < bestScore then best, bestScore = i, score end
      end
    end
  end
  return best
end

return focus
