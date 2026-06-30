# Tom's Peripherals — verified API reference (for PinguOS HD)

Durable, **source-verified** reference so we stop guessing the GPU API. Cross-checked
against the mod's Java engine, official Lua examples, the wiki, mod issues, and live
in-game behaviour (Tom's Peripherals 1.3.x, CC:Tweaked 1.120.0, MC 1.21.1 NeoForge).

**Where the engine source lives:** not a separate Maven lib — it's on the **`api`
branch** of the same repo, at `src/shared/java/com/tom/peripherals/gpu/`
(`BaseGPU.java` = the 2D engine: drawText, rectangles, lines, fonts, windows;
`GPUImpl.java` = images/buffers; `font/Font.java`). `main` pulls it from an off-repo
`srcDir`, which is why it looked "external". The peripheral you wrap (`tm_gpu`) is
`GPUExt extends GPUImpl extends BaseGPU`.

**Sources**
- Engine: https://github.com/tom5454/Toms-Peripherals/blob/api/src/shared/java/com/tom/peripherals/gpu/BaseGPU.java
- Examples: https://github.com/tom5454/Toms-Peripherals/tree/api/examples (`term_emu.lua`, `termEmuTest.lua`, `cc_term_font.lua`, `gpuCursor.lua`, `gpuDraw.lua`)
- Wiki: GPUImpl / GPUExt / LuaImage. Real program: korczoczek/hexcastingCC_viewPattern.
- Gotcha issues: #28 (async refresh), #22 (setFont), #24 (monitor placement), #8 (sync lag)

## Peripheral & physical setup

- GPU type **`tm_gpu`** (`peripheral.find("tm_gpu")`). Monitors are passive **Bitmap
  Monitor** blocks (NOT CC Advanced Monitors). GPU must touch the wall **block-to-block**
  (no cable), on a **horizontal** face, at the **bottom-left corner monitor (front view)**
  to capture the whole wall (wrong corner → partial sub-grid; monitor *below* it → not
  detected, #24).

## Init sequence

```lua
local gpu = peripheral.find("tm_gpu")
gpu.refreshSize()        -- ASYNC: scans the wall a tick later (#28)
sleep(0)                 -- or poll getSize() until > 0; else you read a stale 0x0
gpu.setSize(64)          -- per-block resolution 16..64 (sharper + heavier). W=blocksX*size
local w, h, bw, bh, res = gpu.getSize()   -- pixelsX, pixelsY, blocksX, blocksY, multiplier
gpu.fill(0x111111)
gpu.sync()               -- presents the back-buffer to the physical screens
-- setFont("ascii") ONLY needed before drawChar/custom fonts (#22). drawText is fine without it.
```

## Coordinate system — **1-based** (source-confirmed)

Pixels run **1..W (x)** / **1..H (y)**. `(1,1)` = top-left, `(W,H)` valid, `(0,0)` =
"Out of boundary". `filledRectangle(x,y,w,h,..)` covers columns `x .. x+w-1` (exactly
`w` px); right/bottom clamp to W/H; guard requires `x` in `1..W+1`. **Stay on-screen:
`x + w - 1 <= W` and `y + h - 1 <= H`.** Full-width rect = `filledRectangle(1, y, W, h)`.
- cell→pixel: `px = (col-1)*charW + 1`, `py = (row-1)*charH + 1`
- pixel→cell: `col = floor((px-1)/charW)+1`, `row = floor((py-1)/charH)+1`

## Drawing API (BaseGPU)

```
fill([color])                                  -- clear surface (default 0x000000)
filledRectangle(x, y, w, h, [color])           -- color: packed int OR r,g,b[,a]
rectangle(x, y, w, h, [color])                 -- outline
line / lineS (x1, y1, x2, y2, color)           -- lineS = smooth
drawText(x, y, text, [fg=white], [bg=-1], [size=1], [padding=1]) -> colors packed-int only
drawChar(x, y, charByte, [fg], [bg=-1], [size]) -- needs setFont first
getTextLength(text, [size], [padding]) -> pixelWidth     -- NO getTextHeight exists
drawImage(x, y, image.ref())
createWindow(x, y, w, h) -> sub-canvas (clipped; own buffer; .sync() composites onto parent)
sync()
```

### Text — the correct way (this is what bit us, now source-verified)

- **`bg = -1` (the default) = NO background.** Only lit glyph pixels are drawn → crisp.
  If you pass a real `bg`, drawText fills the glyph's UN-lit pixels *and* the padding with
  it → a solid box that reads as **washed-out gray bars** (a glyph lights ~25% of its
  cell). **Never use drawText's bg for UI.** Paint the cell background yourself with
  `filledRectangle`, then `drawText(x, y, s, fg, -1, size)`.
- **The monitor minifies the GPU texture** (MC mipmap/bilinear), which blends 1px strokes
  toward the background → faint/gray. Mitigate with **`size >= 2`** (or native `setSize(64)`).
- **Font metrics (default `ascii`, source-read from the .bin):** glyph height **8 px**,
  **proportional** width (most glyphs ~5px; advance = `(width+padding)*size` ≈ **6*size**).
  `size` scales both axes by integer pixel replication (no AA). No height getter — hardcode
  `8*size` (ascii) / `16*size` (unicode pages). `term_emu.lua` uses a **9px cell** (8 glyph
  + 1 leading) and 6px column: `charW = size*6`, `charH = size*9`.
- **Center a proportional glyph in its cell:**
  `x = (col-1)*charW + (charW/2+1) - getTextLength(char,size)/2` (drawn char-by-char).
- Canonical per-cell pattern (`term_emu.lua`):
  ```lua
  gpu.filledRectangle((cx-1)*charW+1, (cy-1)*charH+1, charW, charH, bgColor)   -- cell bg
  if char ~= " " then gpu.drawText(px, py, char, fgColor, -1, size) end        -- fg, bg=-1
  ```

### Fonts

- `setFont(name)` loads `<name>.bin`. Ships: **`ascii`** (8px, proportional, default),
  `ascii_sga`, **`unicode_page_00`..`ff`** (16px GNU Unifont; `page_00` = Latin). Pages
  `e0`–`ff` are editable custom slots.
- Crisp monospace for a terminal grid: upload the **6×10 monospace** font from
  `cc_term_font.lua` into an editable page, or `setFont("unicode_page_00")` (uniform 16px).
- **Use `drawText`/`drawChar`, NOT `drawTextSmart`** — the latter auto-loads a font per
  char, renders ASCII at 2× size, mutates the selected font, and is slow.

### Colour

`0xRRGGBB` (24-bit) or `0xFFRRGGBB` both render opaque (engine forces full alpha). Do NOT
pass CC `colors.*` bit-flags (1,2,4,…) — those aren't RGB. CC's default 16-colour palette
in ARGB: white `0xFFF0F0F0`, orange `0xFFF2B233`, magenta `0xFFE57FD8`, lightBlue
`0xFF99B2F2`, yellow `0xFFDEDE6C`, lime `0xFF7FCC19`, pink `0xFFF2B2CC`, gray `0xFF4C4C4C`,
lightGray `0xFF999999`, cyan `0xFF4C99B2`, purple `0xFFB266E5`, blue `0xFF3366CC`, brown
`0xFF7F664C`, green `0xFF57A64E`, red `0xFFCC4C4C`, black `0xFF111111`.

## Images (PNG)

```lua
local of = io.open("x.png", "rb"); local b = of._handle.read(1); local bytes = {}
while b do bytes[#bytes+1] = ("<I1"):unpack(b); b = of._handle.read(1) end
local image = gpu.decodeImage(table.unpack(bytes))
gpu.drawImage(1, 1, image.ref())     -- ALWAYS pass image.ref()
```
`image`: `.ref()`, `.getWidth()/.getHeight()`, `.getRGB/.setRGB`, `.getAsBuffer()` (ARGB,
`pixels[x + width*(y-1)]`, 1-based), `.saveImage()`→ByteBuffer (save PNG), `.free()`.

## Input

- **Touch:** `tm_monitor_touch` → `(side, x, y, sneaking)` in **pixels (1-based)**. Also
  `tm_monitor_mouse_click/_drag/_scroll/_move`. Map to cells with the pixel→cell formula.
- **Keyboard `tm_keyboard`:** prefixed `tm_keyboard_key(side,keyId,held)` / `_key_up` /
  `_char` / `_paste` by default; `setFireNativeEvents(true)` → standard CC `key`/`char`/etc.

## Gotchas

- **#28** `refreshSize()` async → `sleep(0)` / poll before `getSize()`.
- **#22** `drawChar`/custom font NPE without `setFont("ascii")` first (drawText is fine).
- **#8** fast `sync()` = lag/crash → throttle + double-buffer + redraw only changed cells.
- **#24** GPU won't connect to a monitor placed directly below it.
- drawText's y-bounds check omits `*size`, so oversized text near the bottom silently clips.

## The shortcut: reuse `term_emu.lua`

`term_emu.lua` is a **complete CC `term` redirect** on the GPU: two-buffer diffing (only
changed cells redraw → no flicker), `write/blit/clear/clearLine/scroll/setCursorPos/
setTextColor/setBackgroundColor/palette`, blinking cursor, `getSize`, and `mapPixel(x,y)`
(touch px → cell). `termEmuTest.lua` wires GPU(`setSize 64`) + keyboard + `term.redirect`
and runs a full HD CC shell — proof the approach works end-to-end.

**PinguOS HD term shim = adapt `term_emu.lua`**: drop `cc.expect`, wire it to our theme
palette and `gpu.lua`, then in HD mode `term.redirect()` the desktop+apps onto it and
translate `tm_monitor_touch`→`mouse_click` via `mapPixel`. Don't rewrite it.

### Recipe (crisp HD text)
1. Background via `filledRectangle`, then `drawText(x,y,s,fg,-1,size)` (**bg=-1**).
2. `size >= 2` (or `setSize(64)`) so 1px strokes survive monitor minification.
3. Monospace grid: upload the 6×10 font (`cc_term_font.lua`) or `setFont("unicode_page_00")`.
4. Whole character UI/shell: reuse `term_emu.lua` as the `term.redirect` target.
