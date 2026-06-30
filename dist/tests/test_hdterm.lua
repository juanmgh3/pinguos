-- dist/tests/test_hdterm.lua  -- pure cell<->pixel grid math for the HD term shim.
local hd = require("hdterm")

-- grid sizing: how many character cells fit in a pixel surface
T.eq(hd.cols(320, 6), 53, "320px / 6 -> 53 cols")
T.eq(hd.rows(192, 9), 21, "192px / 9 -> 21 rows")
T.eq(hd.cols(321, 6), 53, "floors partial column")

-- cell (1-based) -> pixel (1-based) top-left corner; tm_gpu coords are 1-based
T.eq({ hd.cellToPx(1, 1, 6, 9) }, { 1, 1 }, "cell 1,1 -> px 1,1")
T.eq({ hd.cellToPx(2, 1, 6, 9) }, { 7, 1 }, "cell 2,1 -> px 7,1")
T.eq({ hd.cellToPx(1, 3, 6, 9) }, { 1, 19 }, "cell 1,3 -> px 1,19")

-- pixel (1-based) -> cell (for translating touch coords back to term space)
T.eq({ hd.pxToCell(1, 1, 6, 9) }, { 1, 1 }, "px 1,1 -> cell 1,1")
T.eq({ hd.pxToCell(7, 1, 6, 9) }, { 2, 1 }, "px 7 -> col 2")
T.eq({ hd.pxToCell(21, 19, 6, 9) }, { 4, 3 }, "px 21,19 -> cell 4,3")
