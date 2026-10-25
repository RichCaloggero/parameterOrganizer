-- Saving and loading the user's organization of one effect as text.
-- Plain Lua with no REAPER calls.
--
-- Format: a header line, then one line per item, depth first, fields
-- separated by tabs; depth 0 is directly inside the effect.
--   ParameterOrganizer layout 1
--   plugin <plugin identifier>
--   B <depth> <branch name>
--   P <depth> <parameter index> <original name> <own name, or empty>

local tree = require("tree")
local organizer = require("organizer")

local M = {}

local HEADER = "ParameterOrganizer layout 1"

local function clean(text)
  return (tostring(text or ""):gsub("[\t\r\n]", " "))
end

local function is_user_item(node)
  return node.kind == "branch" or node.kind == "param"
end

-- The text for fx_node's branches and parameters (not, for a container,
-- the effects it holds, which have layouts of their own). The plugin's
-- name is recorded on a "plugin" line, for anyone reading the file.
function M.serialize(fx_node)
  local lines = { HEADER, "plugin\t" .. clean(fx_node.data.plugin_key or fx_node.label) }
  local function add(node, depth)
    for _, child in ipairs(node.children) do
      if child.kind == "branch" then
        lines[#lines + 1] = table.concat({ "B", depth, clean(child.label) }, "\t")
        add(child, depth + 1)
      elseif child.kind == "param" and not child.data.unplaced then
        local d = child.data
        lines[#lines + 1] = table.concat(
          { "P", depth, d.index, clean(d.original_name), clean(d.user_label) }, "\t")
      end
    end
  end
  add(fx_node, 0)
  return table.concat(lines, "\n") .. "\n"
end

local function split_tabs(line)
  local fields = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
  return fields
end

-- Finds the parameter a saved line refers to in this instance of the
-- plugin: by index when the name there still matches, otherwise by name
-- (a plugin update may have reordered its parameters). names maps each
-- index to its name. Returns nil when the parameter can't be found.
local function resolve(names, index, original, used)
  if names[index] == original and not used[index] then return index end
  for i, name in pairs(names) do
    if name == original and not used[i] then return i end
  end
  return nil
end

-- Replaces fx_node's branches and parameters with those in text, for this
-- instance: names maps each of its parameter indexes to its name.
-- Parameters that can't be found are kept, marked missing, so that the
-- layout isn't lost if the plugin is only temporarily different.
-- Returns false, changing nothing, when text isn't a layout.
function M.apply(fx_node, text, names)
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line:gsub("\r$", "") end
  if lines[1] ~= HEADER then return false end

  local kept = {}
  for _, child in ipairs(fx_node.children) do
    if not is_user_item(child) then kept[#kept + 1] = child end
  end
  fx_node.children = {}
  for _, child in ipairs(kept) do tree.add_child(fx_node, child) end

  local parents = { [0] = fx_node }
  local used = {}
  for i = 2, #lines do
    local f = split_tabs(lines[i])
    local depth = tonumber(f[2])
    local parent = depth and parents[depth]
    if parent and f[1] == "B" then
      parents[depth + 1] = tree.add_child(parent, tree.new_node("branch", f[3] or ""))
    elseif parent and f[1] == "P" then
      local saved_index = tonumber(f[3])
      local original = f[4] or ""
      local index = saved_index and resolve(names, saved_index, original, used)
      local node = tree.add_child(parent, tree.new_node("param", "", {
        track = fx_node.data.track,
        fx = fx_node.data.fx,
        fx_guid = fx_node.data.guid,
        index = index or saved_index,
        original_name = original,
        user_label = (f[5] or "") ~= "" and f[5] or nil,
        missing = index == nil or nil,
      }))
      if index then used[index] = true end
      node.label = organizer.param_label(node)
    end
  end
  organizer.refresh_unplaced(fx_node)
  return true
end

return M
