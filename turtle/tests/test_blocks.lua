-- turtle/tests/test_blocks.lua
local blocks = require("blocks")

-- logs
T.ok(blocks.isLog("minecraft:oak_log"), "oak_log is a log")
T.ok(blocks.isLog("minecraft:stripped_birch_log"), "stripped log is a log")
T.ok(not blocks.isLog("minecraft:stone"), "stone is not a log")
T.ok(not blocks.isLog(nil), "nil is not a log")

-- ores
T.ok(blocks.isOre("minecraft:iron_ore"), "iron_ore is ore")
T.ok(blocks.isOre("minecraft:deepslate_diamond_ore"), "deepslate ore is ore")
T.ok(blocks.isOre("minecraft:nether_gold_ore"), "nether ore is ore")
T.ok(blocks.isOre("minecraft:ancient_debris"), "ancient_debris counts as ore")
-- the edge cases that "ore-as-substring" must NOT misfire on
T.ok(not blocks.isOre("minecraft:stone"), "stone is not ore")
T.ok(not blocks.isOre("minecraft:cobblestone"), "cobblestone is not ore")
T.ok(not blocks.isOre("minecraft:redstone_block"), "redstone_block is not ore")
T.ok(not blocks.isOre("minecraft:glowstone"), "glowstone is not ore")
T.ok(not blocks.isOre(nil), "nil is not ore")
-- but the actual redstone ORE is
T.ok(blocks.isOre("minecraft:redstone_ore"), "redstone_ore is ore")
