-- turtle/tests/run.lua  (run from repo root: lua turtle/tests/run.lua)
-- Unit tests for the PURE turtle libs (roles, nav). The job run-loops and api.lua
-- call the turtle API and can only be checked with `luac -p` + tested in-game.
package.path = "turtle/lib/?.lua;./lib/?.lua;" .. package.path
local pass, fail = 0, 0

local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, val in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. dump(val) end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- deep equality that handles dictionaries (the dist/ runner only compares arrays).
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

_G.T = {
  eq = function(got, want, msg)
    if same(got, want) then pass = pass + 1
    else
      fail = fail + 1
      print("FAIL: " .. (msg or ""))
      print("  want: " .. dump(want)); print("  got:  " .. dump(got))
    end
  end,
  ok = function(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. (msg or "")) end
  end,
}

dofile("turtle/tests/test_roles.lua")
dofile("turtle/tests/test_nav.lua")
dofile("turtle/tests/test_blocks.lua")
print(("turtle tests: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
