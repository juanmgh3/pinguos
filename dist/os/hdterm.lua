-- dist/os/hdterm.lua  -- an HD "terminal": emulates a CC character terminal on
-- Tom's pixel surface (via gpu.lua), so ui.lua and every app render in HD with
-- no app changes. The pure grid math below is unit-tested; the shim that drives
-- gpu.* (added next) is verified in-game. See specs/pinguos/hd-command-center.md.
local hdterm = {}

-- ---- pure cell <-> pixel grid math (unit-tested) --------------------------

-- how many character cells fit in a pixel surface
function hdterm.cols(wpx, cw) return math.floor(wpx / cw) end
function hdterm.rows(hpx, ch) return math.floor(hpx / ch) end

-- cell (1-based) -> pixel (1-based) top-left corner. tm_gpu is 1-based (pixel
-- (W,H) is valid, (0,0) is not), same convention as CC's term.
function hdterm.cellToPx(col, row, cw, ch)
  return 1 + (col - 1) * cw, 1 + (row - 1) * ch
end

-- pixel (1-based) -> cell (1-based); maps touch events back to term space
function hdterm.pxToCell(px, py, cw, ch)
  return math.floor((px - 1) / cw) + 1, math.floor((py - 1) / ch) + 1
end

return hdterm
