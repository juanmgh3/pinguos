-- turtle/lib/blocks.lua  -- classify a block by its id name (pure, testable).
-- This is where the "what is this block?" knowledge lives, separated from the
-- turtle calls so it can be unit-tested. Names look like "minecraft:iron_ore".
local blocks = {}

local function has(name, sub)
  return type(name) == "string" and name:lower():find(sub, 1, true) ~= nil
end

function blocks.isLog(name)
  return has(name, "log")           -- oak_log, stripped_birch_log, ...
end

-- Every vanilla ore ends in "_ore" (incl. deepslate_/nether_ variants), EXCEPT
-- ancient_debris (netherite). Note "redstone"/"glowstone" contain "stone", not
-- "ore", so they don't false-positive -- exactly the edge a test guards.
function blocks.isOre(name)
  return has(name, "ore") or has(name, "debris")
end

return blocks
