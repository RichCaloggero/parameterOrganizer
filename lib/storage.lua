-- Where layouts are kept.
--
-- An effect's layout belongs to its plugin type, so it is a file in
-- REAPER's resource folder, ParameterOrganizer/layouts, shared by every
-- instance in every project. A container's own parameters depend on that
-- particular container, so its layout is kept in the project instead
-- (saved when the project is saved).

local M = {}

local SECTION = "ParameterOrganizer"

local function layouts_folder()
  return reaper.GetResourcePath() .. "/ParameterOrganizer/layouts"
end

-- FNV-1a, so that two plugin identifiers that clean up to the same file
-- name still get different files.
local function hash(text)
  local h = 2166136261
  for i = 1, #text do
    h = ((h ~ text:byte(i)) * 16777619) & 0xffffffff
  end
  return string.format("%08x", h)
end

-- A file name for a plugin identifier, readable but safe on any system.
function M.file_name(key)
  local readable = key:gsub("[^%w%-%.]+", "_"):sub(1, 80)
  return readable .. "_" .. hash(key) .. ".txt"
end

local function file_path(key)
  return layouts_folder() .. "/" .. M.file_name(key)
end

-- The saved layout text for an effect's data, or nil.
function M.load(fx_data)
  if fx_data.is_container then
    local ok, text = reaper.GetProjExtState(0, SECTION, "container " .. fx_data.guid)
    if ok == 1 and text ~= "" then return text end
    return nil
  end
  local f = io.open(file_path(fx_data.plugin_key), "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

-- Saves layout text for an effect's data. Returns false on failure.
function M.save(fx_data, text)
  if fx_data.is_container then
    reaper.SetProjExtState(0, SECTION, "container " .. fx_data.guid, text)
    return true
  end
  reaper.RecursiveCreateDirectory(layouts_folder(), 0)
  local f = io.open(file_path(fx_data.plugin_key), "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

return M
