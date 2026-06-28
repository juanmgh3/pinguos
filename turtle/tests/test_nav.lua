-- turtle/tests/test_nav.lua
local nav = require("nav")

local N, E, S, W = nav.HEADINGS[0], nav.HEADINGS[1], nav.HEADINGS[2], nav.HEADINGS[3]

-- delta
T.eq(nav.delta({ x = 0, y = 0, z = 0 }, { x = 3, y = -2, z = 5 }),
  { dx = 3, dy = -2, dz = 5 }, "delta")

-- headingFromMove
T.eq(nav.headingFromMove({ x = 0, y = 64, z = 0 }, { x = 1, y = 64, z = 0 }), E, "move east")
T.eq(nav.headingFromMove({ x = 0, y = 64, z = 0 }, { x = 0, y = 64, z = -1 }), N, "move north")
T.eq(nav.headingFromMove({ x = 0, y = 64, z = 0 }, { x = 0, y = 65, z = 0 }), nil, "vertical move -> nil")

-- headingIndex
T.eq(nav.headingIndex(N), 0, "north index 0")
T.eq(nav.headingIndex(E), 1, "east index 1")
T.eq(nav.headingIndex(S), 2, "south index 2")
T.eq(nav.headingIndex(W), 3, "west index 3")
T.eq(nav.headingIndex({ dx = 2, dz = 0 }), nil, "non-unit -> nil")

-- turns: 0 none, 1 right, -1 left, 2 about-face
T.eq(nav.turns(N, N), 0, "north->north none")
T.eq(nav.turns(N, E), 1, "north->east right")
T.eq(nav.turns(N, W), -1, "north->west left")
T.eq(nav.turns(N, S), 2, "north->south about-face")
T.eq(nav.turns(W, N), 1, "west->north right")
T.eq(nav.turns(E, N), -1, "east->north left")

-- headingForAxis
T.eq(nav.headingForAxis("x", 5), E, "axis x+ -> east")
T.eq(nav.headingForAxis("x", -5), W, "axis x- -> west")
T.eq(nav.headingForAxis("z", 5), S, "axis z+ -> south")
T.eq(nav.headingForAxis("z", -3), N, "axis z- -> north")
T.eq(nav.headingForAxis("x", 0), nil, "axis 0 -> nil")
