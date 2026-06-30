-- dist/tests/test_focus.lua  -- pure spatial focus navigation (desktop grid).
local focus = require("focus")

-- center: integer centre cell of a region
T.eq({ focus.center({ x = 2, y = 3, w = 9, h = 3 }) }, { 6, 4 }, "center of 9x3 tile")
T.eq({ focus.center({ x = 1, y = 1, w = 1, h = 1 }) }, { 1, 1 }, "center of 1x1")

-- a 2x2 grid of tiles, like the desktop: 1,2 top row; 3,4 bottom row
local grid = {
  { x = 2,  y = 3, w = 9, h = 3 },  -- 1 top-left
  { x = 14, y = 3, w = 9, h = 3 },  -- 2 top-right
  { x = 2,  y = 9, w = 9, h = 3 },  -- 3 bottom-left
  { x = 14, y = 9, w = 9, h = 3 },  -- 4 bottom-right
}
T.eq(focus.spatial(grid, 1, "right"), 2, "right from 1 -> 2")
T.eq(focus.spatial(grid, 1, "down"),  3, "down from 1 -> 3")
T.eq(focus.spatial(grid, 2, "left"),  1, "left from 2 -> 1")
T.eq(focus.spatial(grid, 4, "up"),    2, "up from 4 -> 2")
T.eq(focus.spatial(grid, 1, "left"),  1, "no tile left of 1 -> stays")
T.eq(focus.spatial(grid, 1, "up"),    1, "no tile above 1 -> stays")

-- guards
T.eq(focus.spatial({}, 1, "right"),   0, "empty list -> 0")
T.eq(focus.spatial(grid, 0, "right"), 1, "bad index -> first")

-- cycle: Tab-order wrap-around
T.eq(focus.cycle(3, 1, 1),  2, "cycle next 1 -> 2")
T.eq(focus.cycle(3, 3, 1),  1, "cycle next wraps 3 -> 1")
T.eq(focus.cycle(3, 1, -1), 3, "cycle prev wraps 1 -> 3")
T.eq(focus.cycle(3, 2, -1), 1, "cycle prev 2 -> 1")
T.eq(focus.cycle(0, 1, 1),  0, "cycle empty -> 0")
T.eq(focus.cycle(3, 9, 1),  1, "cycle bad index -> first")
