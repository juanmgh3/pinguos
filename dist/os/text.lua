-- dist/os/text.lua
local text = {}

local function wrapParagraph(s, width, out)
  local line = ""
  for word in s:gmatch("%S+") do
    while #word > width do
      if line ~= "" then out[#out + 1] = line; line = "" end
      out[#out + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
end

function text.wrap(s, width)
  if width < 1 then width = 1 end
  local out = {}
  if s == "" then return out end
  for line in (s .. "\n"):gmatch("(.-)\n") do
    if line == "" then out[#out + 1] = "" else wrapParagraph(line, width, out) end
  end
  return out
end

function text.truncate(s, width)
  if #s <= width then return s end
  return s:sub(1, width)
end

function text.ljust(s, width)
  if #s >= width then return s end
  return s .. string.rep(" ", width - #s)
end

function text.center(s, width)
  if #s >= width then return s end
  local pad = width - #s
  local left = math.floor(pad / 2)
  return string.rep(" ", left) .. s .. string.rep(" ", pad - left)
end

return text
