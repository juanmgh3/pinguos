-- turtle/lib/roles.lua  -- map an equipped tool to a fleet role (pure, testable)
local roles = {}

roles.ALL = {
  "mineria", "tala", "ataque", "excavacion", "granja", "transporte", "generico",
}
roles.DEFAULT = "generico"

-- Order matters: "pickaxe" CONTAINS "axe", so pickaxe must be matched first or an
-- axe rule would steal every pickaxe. This ordering bug is exactly why this is a
-- pure, tested module instead of an inline `if`.
roles.RULES = {
  { match = "pickaxe", role = "mineria" },
  { match = "axe",     role = "tala" },
  { match = "sword",   role = "ataque" },
  { match = "shovel",  role = "excavacion" },
  { match = "hoe",     role = "granja" },
}

-- name: a tool id like "minecraft:diamond_pickaxe". Returns a role string or nil.
function roles.fromToolName(name)
  if type(name) ~= "string" then return nil end
  local n = name:lower()
  for _, r in ipairs(roles.RULES) do
    if n:find(r.match, 1, true) then return r.role end   -- plain find, no patterns
  end
  return nil
end

-- detail: the table turtle.getEquippedLeft/Right returns (has a `.name` field).
function roles.fromDetail(detail)
  if type(detail) ~= "table" then return nil end
  return roles.fromToolName(detail.name)
end

function roles.isValid(role)
  for _, r in ipairs(roles.ALL) do if r == role then return true end end
  return false
end

return roles
