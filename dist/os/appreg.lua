-- dist/os/appreg.lua
local appreg = {}

function appreg.validate(app)
  if type(app) ~= "table" then return false, "not a table" end
  if type(app.id) ~= "string" or app.id == "" then return false, "missing id" end
  if type(app.name) ~= "string" or app.name == "" then return false, "missing name" end
  if type(app.run) ~= "function" then return false, "missing run()" end
  return true
end

function appreg.collect(files, load)
  local apps, errs = {}, {}
  for _, f in ipairs(files) do
    local ok, res = load(f.path)
    if not ok then
      errs[#errs + 1] = { id = f.id, err = tostring(res) }
    else
      local valid, why = appreg.validate(res)
      if valid then
        res.id = res.id or f.id
        apps[#apps + 1] = res
      else
        errs[#errs + 1] = { id = f.id, err = why }
      end
    end
  end
  table.sort(apps, function(a, b) return a.name < b.name end)
  return apps, errs
end

return appreg
