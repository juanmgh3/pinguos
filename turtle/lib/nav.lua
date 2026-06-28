-- turtle/lib/nav.lua  -- GPS navigation math (pure, testable)
--
-- Minecraft cardinal mapping: north = -z, south = +z, east = +x, west = -x.
-- A heading is a unit vector { dx, dz } with one component 0. Its "index" is the
-- clockwise position from north: north=0, east=1, south=2, west=3. Keeping all of
-- this as pure functions means the goto job's turning logic can be unit-tested
-- without a turtle (the part that actually calls turtle.turnRight cannot be).
local nav = {}

nav.HEADINGS = {
  [0] = { dx = 0,  dz = -1 }, -- north
  [1] = { dx = 1,  dz = 0  }, -- east
  [2] = { dx = 0,  dz = 1  }, -- south
  [3] = { dx = -1, dz = 0  }, -- west
}

local function sign(n)
  if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end
end
nav.sign = sign

-- vector from a to b; positions are CC gps tables { x, y, z }.
function nav.delta(a, b)
  return { dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z }
end

-- which heading did we just move along? before/after are one step apart.
-- Returns a heading { dx, dz }, or nil if the move was purely vertical.
function nav.headingFromMove(before, after)
  local dx, dz = sign(after.x - before.x), sign(after.z - before.z)
  if dx == 0 and dz == 0 then return nil end
  return { dx = dx, dz = dz }
end

-- heading vector -> clockwise index 0..3, or nil if it isn't a unit cardinal.
function nav.headingIndex(h)
  if type(h) ~= "table" then return nil end
  for i = 0, 3 do
    if nav.HEADINGS[i].dx == h.dx and nav.HEADINGS[i].dz == h.dz then return i end
  end
  return nil
end

function nav.headingFromIndex(i)
  return nav.HEADINGS[i % 4]
end

-- How to rotate from `cur` heading to `want` heading. Returns:
--   0  = already facing it,  1 = one turnRight,  -1 = one turnLeft,  2 = about-face.
function nav.turns(cur, want)
  local ci, wi = nav.headingIndex(cur), nav.headingIndex(want)
  if not ci or not wi then return 0 end
  local d = (wi - ci) % 4
  if d == 0 then return 0
  elseif d == 1 then return 1
  elseif d == 2 then return 2
  else return -1 end
end

-- The heading you must face to walk a signed distance along an axis ("x" or "z").
-- Returns a heading, or nil if the distance is 0 / axis unknown.
function nav.headingForAxis(axis, d)
  if d == 0 then return nil end
  if axis == "x" then return { dx = sign(d), dz = 0 } end
  if axis == "z" then return { dx = 0, dz = sign(d) } end
  return nil
end

return nav
