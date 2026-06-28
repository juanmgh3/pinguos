-- dist/tests/run.lua  (run from repo root: lua dist/tests/run.lua)
package.path = "dist/os/?.lua;./os/?.lua;" .. package.path
local pass, fail = 0, 0
local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local p = {}; for i = 1, #v do p[i] = dump(v[i]) end
  return "{" .. table.concat(p, ", ") .. "}"
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if not same(a[i], b[i]) then return false end end
  return true
end
_G.T = {
  eq = function(got, want, msg)
    if same(got, want) then pass = pass + 1
    else fail = fail + 1
      print("FAIL: " .. (msg or ""))
      print("  want: " .. dump(want)); print("  got:  " .. dump(got))
    end
  end,
  ok = function(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. (msg or "")) end
  end,
}
dofile("dist/tests/test_text.lua")
dofile("dist/tests/test_appreg.lua")
print(("PinguOS tests: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
