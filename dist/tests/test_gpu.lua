-- dist/tests/test_gpu.lua  -- pure-logic of the HD render layer (gpu.lua).
-- The tm_gpu I/O (attach/draw/present) is verified in-game, not here.
local gpu = require("gpu")

-- pack: ARGB int from components; alpha defaults to opaque (0xFF)
T.eq(gpu.pack(0xF0, 0xF0, 0xF0), 0xFFF0F0F0, "pack rgb -> opaque alpha")
T.eq(gpu.pack(0x11, 0x22, 0x33, 0x44), 0x44112233, "pack rgba explicit alpha")
T.eq(gpu.pack(0, 0, 0), 0xFF000000, "pack black opaque")

-- fromCC: map a CC palette colour (power-of-two value) to opaque ARGB
T.eq(gpu.fromCC(0x1), 0xFFF0F0F0, "white -> argb")     -- colors.white
T.eq(gpu.fromCC(0x8000), 0xFF111111, "black -> argb")  -- colors.black
T.eq(gpu.fromCC(0x200), 0xFF4C99B2, "cyan -> argb")    -- colors.cyan
T.eq(gpu.fromCC(0x4000), 0xFFCC4C4C, "red -> argb")    -- colors.red
T.eq(gpu.fromCC(nil), 0xFFF0F0F0, "unknown -> white fallback")

-- barFill: filled pixel width of a w-wide bar at fraction pct (clamped, floored)
T.eq(gpu.barFill(100, 0.5), 50, "half of 100")
T.eq(gpu.barFill(100, 0), 0, "empty")
T.eq(gpu.barFill(100, 1), 100, "full")
T.eq(gpu.barFill(100, 1.5), 100, "over -> clamped full")
T.eq(gpu.barFill(100, -0.2), 0, "under -> clamped empty")
T.eq(gpu.barFill(10, 0.55), 5, "floors partial (5.5 -> 5)")
