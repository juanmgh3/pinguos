-- dist/os/geo.lua  (pure math; no CC APIs, unit-tested locally)
local geo = {}

-- two-arg arctangent: Lua 5.1 has math.atan2; Lua 5.3+ folds it into math.atan
local atan2 = math.atan2 or math.atan

function geo.distance(a, b)
  local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Minecraft axes: North = -Z, East = +X, South = +Z, West = -X.
function geo.compass(from, to)
  local dx, dz = to.x - from.x, to.z - from.z
  if dx == 0 and dz == 0 then return "-" end
  local deg = math.deg(atan2(dx, -dz))
  if deg < 0 then deg = deg + 360 end
  local idx = math.floor((deg + 22.5) / 45) % 8
  return DIRS[idx + 1]
end

function geo.heading(prev, cur)
  return geo.compass(prev, cur)
end

-- Project a world point onto a w x h minimap centered on the player.
-- Returns mx, my (1-based cells) or nil if off-map. 1 cell = `scale` blocks.
function geo.toMinimap(player, point, w, h, scale)
  local cx, cy = math.ceil(w / 2), math.ceil(h / 2)
  local mx = cx + math.floor((point.x - player.x) / scale + 0.5)
  local my = cy + math.floor((point.z - player.z) / scale + 0.5)
  if mx < 1 or mx > w or my < 1 or my > h then return nil end
  return mx, my
end

return geo
