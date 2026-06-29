-- turtle/jobs/fell-tree.lua  -- fell the single tree in front (climb, descend,
-- replant). The felling logic lives in api.chopTree so lumber/tree-farm share it.
return {
  id = "fell-tree",
  label = "Fell tree",
  roles = { tala = true },
  params = {},
  run = function(api)
    local h = api.chopTree()
    if h == 0 then return false, "no hay arbol delante" end
    api.progress(100, "arbol talado")
    return true, ("arbol de altura %d talado"):format(h)
  end,
}
