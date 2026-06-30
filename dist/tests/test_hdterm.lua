-- dist/tests/test_hdterm.lua  -- pure cell<->pixel grid math for the HD term shim.
local hd = require("hdterm")

-- grid sizing: how many character cells fit in a pixel surface
T.eq(hd.cols(320, 6), 53, "320px / 6 -> 53 cols")
T.eq(hd.rows(192, 9), 21, "192px / 9 -> 21 rows")
T.eq(hd.cols(321, 6), 53, "floors partial column")

-- cell (1-based, like CC term) -> pixel (0-based) top-left corner
T.eq({ hd.cellToPx(1, 1, 6, 9) }, { 0, 0 }, "cell 1,1 -> px 0,0")
T.eq({ hd.cellToPx(2, 1, 6, 9) }, { 6, 0 }, "cell 2,1 -> px 6,0")
T.eq({ hd.cellToPx(1, 3, 6, 9) }, { 0, 18 }, "cell 1,3 -> px 0,18")

-- pixel -> cell (for translating touch coords back to term space)
T.eq({ hd.pxToCell(0, 0, 6, 9) }, { 1, 1 }, "px 0,0 -> cell 1,1")
T.eq({ hd.pxToCell(7, 0, 6, 9) }, { 2, 1 }, "px 7 -> col 2")
T.eq({ hd.pxToCell(20, 18, 6, 9) }, { 4, 3 }, "px 20,18 -> cell 4,3")
