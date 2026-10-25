-- Multiple selection. Plain Lua with no REAPER calls.
--
-- Normal mode works like a Windows list, within one level: Shift with the
-- arrows selects a range from the anchor (replacing the selection),
-- Shift+Space toggles the focused item, Control+A selects every leaf at the
-- level, and the caller clears the selection on any plain move.
--
-- Multiselect mode (sel.sticky) keeps the selection while moving, and it
-- can span levels within one effect. Ranges and Control+A add to it.
--
-- A selection is { sticky, scope, set, anchor, anchor_container, base }:
-- set holds the selected nodes, all inside scope (the level in normal
-- mode, the enclosing effect in multiselect mode). A range runs from
-- anchor (an index in anchor_container) to the focus, added to base, the
-- selection as it was when the anchor was set.

local tree = require("tree")

local M = {}

function M.new()
  return { sticky = false, scope = nil, set = {}, anchor = nil, anchor_container = nil, base = {} }
end

-- Clears the selection; the mode stays as it is.
function M.clear(sel)
  sel.scope, sel.set, sel.anchor, sel.anchor_container, sel.base = nil, {}, nil, nil, {}
end

function M.count(sel)
  local n = 0
  for _ in pairs(sel.set) do n = n + 1 end
  return n
end

function M.is_selected(sel, node)
  return node ~= nil and sel.set[node] == true
end

local function copy(set)
  local result = {}
  for node in pairs(set) do result[node] = true end
  return result
end

-- The next range starts afresh from wherever the focus is then.
function M.forget_anchor(sel)
  sel.anchor, sel.anchor_container = nil, nil
end

-- Makes sure the selection belongs where the cursor is: the same level,
-- or in multiselect mode the same effect. Elsewhere it starts afresh.
local function same_scope(sel, cursor)
  local scope = cursor.container
  if sel.sticky then scope = tree.enclosing(cursor.container, "fx") or cursor.container end
  if sel.scope ~= scope then
    M.clear(sel)
    sel.scope = scope
  end
  if sel.anchor_container ~= cursor.container then M.forget_anchor(sel) end
end

-- Shift+arrows, Shift+Home and Shift+End: the cursor has moved from
-- old_index; select everything from the anchor to the new focus. In normal
-- mode the range replaces the selection; in multiselect mode it is added.
function M.extend(sel, cursor, old_index)
  same_scope(sel, cursor)
  if not sel.anchor then
    sel.anchor, sel.anchor_container = old_index, cursor.container
    sel.base = sel.sticky and copy(sel.set) or {}
  end
  sel.set = copy(sel.base)
  local children = cursor.container.children
  local from, to = math.min(sel.anchor, cursor.index), math.max(sel.anchor, cursor.index)
  for i = math.max(from, 1), math.min(to, #children) do sel.set[children[i]] = true end
end

-- Shift+Space: select or unselect the focused item, which becomes the
-- anchor for the next range. Returns true when it is now selected.
function M.toggle(sel, cursor)
  local node = tree.focused(cursor)
  if not node then return false end
  same_scope(sel, cursor)
  sel.set[node] = not sel.set[node] or nil
  sel.anchor, sel.anchor_container = cursor.index, cursor.container
  sel.base = sel.sticky and copy(sel.set) or {}
  return sel.set[node] == true
end

-- Control+A: every leaf (parameter) at the level, skipping branches;
-- added to the selection in multiselect mode. Returns how many leaves
-- there are at the level.
function M.select_leaves(sel, cursor)
  same_scope(sel, cursor)
  if not sel.sticky then sel.set = {} end
  local count = 0
  for _, child in ipairs(cursor.container.children) do
    if tree.is_leaf(child) then
      sel.set[child] = true
      count = count + 1
    end
  end
  M.forget_anchor(sel)
  return count
end

-- The selected nodes, in tree order.
function M.nodes(sel)
  local list = {}
  if not sel.scope then return list end
  tree.walk(sel.scope, function(n)
    if sel.set[n] then list[#list + 1] = n end
  end)
  return list
end

-- True when node is still in the tree under scope. A rebuilt level drops
-- its old nodes from its children, though they keep their parent link.
local function attached(scope, node)
  while node ~= scope do
    if not node.parent or not tree.index_of(node) then return false end
    node = node.parent
  end
  return true
end

-- After part of the tree was rebuilt: selected nodes that are no longer in
-- the scope are dropped, and map(old) can name a node that replaced one.
function M.update(sel, map)
  if not sel.scope then return end
  local set = {}
  for node in pairs(sel.set) do
    local now = map and map(node) or node
    if attached(sel.scope, now) then set[now] = true end
  end
  sel.set = set
  M.forget_anchor(sel)
end

return M
