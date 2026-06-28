-- turtle/tests/test_roles.lua
local roles = require("roles")

T.eq(roles.fromToolName("minecraft:diamond_pickaxe"), "mineria", "pickaxe -> mineria")
T.eq(roles.fromToolName("minecraft:diamond_axe"), "tala", "axe -> tala")
-- regression: "pickaxe" contains "axe"; it must NOT be classified as tala.
T.ok(roles.fromToolName("minecraft:diamond_pickaxe") ~= "tala", "pickaxe is not tala")
T.eq(roles.fromToolName("minecraft:netherite_sword"), "ataque", "sword -> ataque")
T.eq(roles.fromToolName("minecraft:diamond_shovel"), "excavacion", "shovel -> excavacion")
T.eq(roles.fromToolName("minecraft:diamond_hoe"), "granja", "hoe -> granja")
T.eq(roles.fromToolName("minecraft:stick"), nil, "unknown tool -> nil")
T.eq(roles.fromToolName(nil), nil, "nil name -> nil")

T.eq(roles.fromDetail({ name = "minecraft:diamond_pickaxe" }), "mineria", "fromDetail pickaxe")
T.eq(roles.fromDetail(nil), nil, "fromDetail nil")
T.eq(roles.fromDetail("nope"), nil, "fromDetail non-table")

T.ok(roles.isValid("mineria"), "mineria is valid")
T.ok(roles.isValid("generico"), "generico is valid")
T.ok(not roles.isValid("wizard"), "wizard is not a role")
