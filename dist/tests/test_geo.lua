-- dist/tests/test_geo.lua
local geo = require("geo")

-- distance (3-4-5)
T.eq(geo.distance({ x = 0, y = 0, z = 0 }, { x = 3, y = 0, z = 4 }), 5, "distance 3-4-5")
T.eq(geo.distance({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }), 0, "distance zero")

-- compass: N=-Z, E=+X, S=+Z, W=-X
T.eq(geo.compass({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -10 }), "N", "north")
T.eq(geo.compass({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }), "E", "east")
T.eq(geo.compass({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 10 }), "S", "south")
T.eq(geo.compass({ x = 0, y = 0, z = 0 }, { x = -10, y = 0, z = 0 }), "W", "west")
T.eq(geo.compass({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = -10 }), "NE", "northeast")
T.eq(geo.compass({ x = 5, y = 0, z = 5 }, { x = 5, y = 0, z = 5 }), "-", "same point")

-- heading = direction of travel
T.eq(geo.heading({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -5 }), "N", "heading north")
T.eq(geo.heading({ x = 5, y = 0, z = 5 }, { x = 5, y = 0, z = 5 }), "-", "no movement")

-- toMinimap: 11x11, player at center (6,6), scale 1
local mx, my = geo.toMinimap({ x = 100, y = 0, z = 100 }, { x = 100, y = 0, z = 100 }, 11, 11, 1)
T.eq(mx, 6, "self mx center"); T.eq(my, 6, "self my center")
mx, my = geo.toMinimap({ x = 100, y = 0, z = 100 }, { x = 103, y = 0, z = 100 }, 11, 11, 1)
T.eq(mx, 9, "east 3 -> mx 9"); T.eq(my, 6, "east my same")
mx, my = geo.toMinimap({ x = 100, y = 0, z = 100 }, { x = 100, y = 0, z = 95 }, 11, 11, 1)
T.eq(mx, 6, "north mx same"); T.eq(my, 1, "north 5 -> my 1")
T.eq(geo.toMinimap({ x = 0, y = 0, z = 0 }, { x = 999, y = 0, z = 0 }, 11, 11, 1), nil, "off-map -> nil")
