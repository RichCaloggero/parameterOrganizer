-- Multiple selection within one level of the tree, Windows style:
-- Shift with the arrows extends a range from the anchor, Shift+Space
-- toggles the focused item, Control+A selects every leaf at the level.
-- Plain Lua with no REAPER calls.
--
-- A selection is { container, anchor, set }: set holds the selected
-- nodes, all children of container; anchor is the index ranges start from.

local tree = require("tree")

local M = {}

function M.new()
  return { container = nil, anchor = nil, set = {} }
end

function M.clear(sel)
  sel.container, sel.anchor, sel.set = nil, nil, {}
end

function M.count(sel)
  local n = 0
  for _ in pairs(sel.set) do n = n + 1 end
  return n
end

function M.is_selected(sel, node)
  return node ~= nil and sel.set[node] == true
end

-- A selection belongs to one level: moving to another level starts afresh.
local function same_level(sel, cursor)
  if sel.container ~= cursor.container then
    M.clear(sel)
    sel.container = cursor.container
  end
end

-- Shift+arrows, Shift+Home and Shift+End: the cursor has moved from
-- old_index; select everything from the anchor (the item where the range
-- started) to the new focus, replacing any earlier selection.
function M.extend(sel, cursor, old_index)
  same_level(sel, cursor)
  sel.anchor = sel.anchor or old_index
  sel.set = {}
  local children = cursor.container.children
  local from, to = math.min(sel.anchor, cursor.index), math.max(sel.anchor, cursor.index)
  for i = math.max(from, 1), math.min(to, #children) do sel.set[children[i]] = true end
end

-- Shift+Space: select or unselect the focused item, which becomes the
-- anchor for the next range. Returns true when it is now selected.
function M.toggle(sel, cursor)
  local node = tree.focused(cursor)
  if not node then return false end
  same_level(sel, cursor)
  sel.anchor = cursor.index
  sel.set[node] = not sel.set[node] or nil
  return sel.set[node] == true
end

-- Control+A: every leaf (parameter) at the level, skipping branches.
-- Returns how many were selected.
function M.select_leaves(sel, cursor)
  same_level(sel, cursor)
  sel.set = {}
  for _, child in ipairs(cursor.container.children) do
    if tree.is_leaf(child) then sel.set[child] = true end
  end
  return M.count(sel)
end

-- The selected nodes, in the order they appear at their level.
function M.nodes(sel)
  local list = {}
  if not sel.container then return list end
  for _, child in ipairs(sel.container.children) do
    if sel.set[child] then list[#list + 1] = child end
  end
  return list
end

return M
