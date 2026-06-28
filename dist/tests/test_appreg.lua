-- dist/tests/test_appreg.lua
local appreg = require("appreg")
T.ok(appreg.validate({ id = "x", name = "X", run = function() end }), "valid app")
T.ok(not appreg.validate({}), "missing id invalid")
T.ok(not appreg.validate("nope"), "non-table invalid")
T.ok(not appreg.validate({ id = "x", name = "X" }), "missing run invalid")

local files = {
  { id = "good", path = "good" },
  { id = "boom", path = "boom" },
  { id = "bad",  path = "bad" },
}
local function load(path)
  if path == "good" then return true, { id = "good", name = "Good", run = function() end } end
  if path == "boom" then return false, "syntax error" end
  return true, { name = "NoRun" } -- invalid: no run()
end
local apps, errs = appreg.collect(files, load)
T.eq(#apps, 1, "one valid app")
T.eq(apps[1].name, "Good", "valid app kept")
T.eq(#errs, 2, "two rejected")
