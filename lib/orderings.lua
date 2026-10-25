-- Named orderings: several saved layouts for one plugin type (or one
-- container), and which of them is active. Plain Lua with no REAPER calls.
--
-- "Original" is always available and is not stored: it is the effect with
-- no branches, every parameter unplaced in source order. A collection is
-- { active = name or nil (Original), list = { { name, text }, ... } },
-- where text is a layout as layout.lua writes it.
--
-- Format: a header line, the active ordering's name (empty for Original),
-- then each ordering: a line "ordering <name>" followed by its layout.
--   ParameterOrganizer orderings 1
--   active <name>
--   ordering <name>
--   ParameterOrganizer layout 1
--   ...

local M = {}

M.ORIGINAL = "Original"
M.EMPTY_LAYOUT = "ParameterOrganizer layout 1\n"

local HEADER = "ParameterOrganizer orderings 1"
local LAYOUT_HEADER = "ParameterOrganizer layout 1"

local function clean(text)
  return (tostring(text or ""):gsub("[\t\r\n]", " "))
end

function M.new()
  return { active = nil, list = {} }
end

local function find(coll, name)
  for i, o in ipairs(coll.list) do
    if o.name:lower() == name:lower() then return o, i end
  end
  return nil
end

-- Reads saved text: a collection, or (from before orderings existed) a
-- single layout, which becomes an active ordering called "Ordering 1".
-- nil or unreadable text gives an empty collection, on Original.
function M.parse(text)
  local coll = M.new()
  if not text then return coll end
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = (line:gsub("\r$", "")) end

  if lines[1] == LAYOUT_HEADER then
    coll.list[1] = { name = "Ordering 1", text = text }
    coll.active = "Ordering 1"
    return coll
  end
  if lines[1] ~= HEADER then return coll end

  local active, current
  for i = 2, #lines do
    local line = lines[i]
    local name = line:match("^ordering\t(.*)$")
    if name then
      current = { name = name, lines = {} }
      coll.list[#coll.list + 1] = current
    elseif current then
      current.lines[#current.lines + 1] = line
    else
      active = line:match("^active\t(.*)$") or active
    end
  end
  for _, o in ipairs(coll.list) do
    o.text = table.concat(o.lines, "\n") .. "\n"
    o.lines = nil
  end
  if active and active ~= "" and find(coll, active) then coll.active = find(coll, active).name end
  return coll
end

function M.serialize(coll)
  local lines = { HEADER, "active\t" .. clean(coll.active) }
  for _, o in ipairs(coll.list) do
    lines[#lines + 1] = "ordering\t" .. clean(o.name)
    lines[#lines + 1] = (o.text:gsub("\n$", ""))
  end
  return table.concat(lines, "\n") .. "\n"
end

-- Every name, Original first.
function M.names(coll)
  local names = { M.ORIGINAL }
  for _, o in ipairs(coll.list) do names[#names + 1] = o.name end
  return names
end

-- The layout text for a name; Original's is an empty layout.
function M.text(coll, name)
  if not name or name:lower() == M.ORIGINAL:lower() then return M.EMPTY_LAYOUT end
  local o = find(coll, name)
  return o and o.text
end

-- True when name can be given to a new or renamed ordering.
-- Returns false and a reason to speak otherwise.
function M.can_use_name(coll, name)
  if name == "" then return false, "A name is needed" end
  if name:lower() == M.ORIGINAL:lower() or find(coll, name) then
    return false, name .. " already exists"
  end
  return true
end

-- The first unused name "Ordering N".
function M.new_name(coll)
  local n = 1
  while find(coll, "Ordering " .. n) do n = n + 1 end
  return "Ordering " .. n
end

-- A free name for a copy of base: "base copy", else "base copy 2", ...
function M.copy_name(coll, base)
  local name = base .. " copy"
  local n = 1
  while not M.can_use_name(coll, name) do
    n = n + 1
    name = base .. " copy " .. n
  end
  return name
end

-- Adds an ordering at position in the list (Original not counted;
-- default: the end). The caller checks the name first.
function M.add(coll, name, text, position)
  table.insert(coll.list, position or #coll.list + 1, { name = clean(name), text = text })
end

-- Replaces the layout text of the active ordering (never Original).
function M.set_active_text(coll, text)
  local o = coll.active and find(coll, coll.active)
  if o then o.text = text end
end

-- name is nil or "Original" for Original.
function M.set_active(coll, name)
  if not name or name:lower() == M.ORIGINAL:lower() then
    coll.active = nil
  else
    coll.active = find(coll, name).name
  end
end

function M.rename(coll, old, new)
  local o = find(coll, old)
  if coll.active == o.name then coll.active = clean(new) end
  o.name = clean(new)
end

-- Removes an ordering; if it was active, Original becomes active.
function M.remove(coll, name)
  local o, i = find(coll, name)
  if not o then return end
  table.remove(coll.list, i)
  if coll.active == o.name then coll.active = nil end
end

-- True for Original, which can't be renamed or deleted.
function M.is_original(name)
  return name == nil or name:lower() == M.ORIGINAL:lower()
end

return M
