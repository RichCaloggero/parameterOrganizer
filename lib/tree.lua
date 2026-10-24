-- Tree nodes and keyboard navigation for Parameter Organizer.
-- Plain Lua with no REAPER calls, so it can be tested outside REAPER.
--
-- A node is { kind, label, data, parent, children }.
-- kind is "root", "track", "fx", "branch" or "param"; only "param" is a leaf.
--
-- A cursor is { container, index }: the focused item is
-- container.children[index]. An empty container is entered with index 0,
-- the "empty" position, so Control+N or Control+V can create its first item.

local M = {}

function M.new_node(kind, label, data)
  return { kind = kind, label = label or "", data = data or {}, parent = nil, children = {} }
end

function M.is_leaf(node)
  return node.kind == "param"
end

function M.index_of(node)
  local parent = node.parent
  if not parent then return nil end
  for i, child in ipairs(parent.children) do
    if child == node then return i end
  end
  return nil
end

-- Inserts child into parent at position (default: the end) and returns it.
function M.add_child(parent, child, position)
  if child.parent then M.detach(child) end
  position = position or #parent.children + 1
  table.insert(parent.children, position, child)
  child.parent = parent
  return child
end

-- Removes node from its parent and returns it.
function M.detach(node)
  local i = M.index_of(node)
  if i then table.remove(node.parent.children, i) end
  node.parent = nil
  return node
end

-- Ancestors from the parent upwards, ending at the root.
function M.ancestors(node)
  local list = {}
  local p = node.parent
  while p do
    list[#list + 1] = p
    p = p.parent
  end
  return list
end

-- Nearest ancestor (or the node itself) of the given kind.
function M.enclosing(node, kind)
  local n = node
  while n do
    if n.kind == kind then return n end
    n = n.parent
  end
  return nil
end

-- True when other is node itself or one of its descendants.
function M.contains(node, other)
  while other do
    if other == node then return true end
    other = other.parent
  end
  return false
end

-- Calls visit(node) for node and all descendants, depth first.
-- Stops early and returns the node when visit returns true.
function M.walk(node, visit)
  if visit(node) then return node end
  for _, child in ipairs(node.children) do
    local found = M.walk(child, visit)
    if found then return found end
  end
  return nil
end

---------------------------------------------------------------------------
-- Cursor

function M.new_cursor(root)
  return { container = root, index = #root.children > 0 and 1 or 0 }
end

-- The focused node, or nil on the empty position.
function M.focused(cursor)
  return cursor.container.children[cursor.index]
end

-- Position and count at the current level, for "3 of 8".
function M.position(cursor)
  return cursor.index, #cursor.container.children
end

function M.focus_node(cursor, node)
  cursor.container = node.parent
  cursor.index = M.index_of(node)
end

-- Movement functions return false when there is nowhere to go,
-- leaving the cursor unchanged, so the caller can announce the edge.

function M.move_next(cursor)
  if cursor.index >= #cursor.container.children then return false end
  cursor.index = cursor.index + 1
  return true
end

function M.move_prev(cursor)
  if cursor.index <= 1 then return false end
  cursor.index = cursor.index - 1
  return true
end

function M.move_first(cursor)
  if #cursor.container.children == 0 then return false end
  cursor.index = 1
  return true
end

function M.move_last(cursor)
  if #cursor.container.children == 0 then return false end
  cursor.index = #cursor.container.children
  return true
end

-- Right: enter the focused non-leaf node, focusing its first child
-- or its empty position.
function M.enter(cursor)
  local node = M.focused(cursor)
  if not node or M.is_leaf(node) then return false end
  cursor.container = node
  cursor.index = #node.children > 0 and 1 or 0
  return true
end

-- Left: focus the parent of the current level.
function M.leave(cursor)
  local container = cursor.container
  if not container.parent then return false end
  M.focus_node(cursor, container)
  return true
end

-- Type-ahead: the next item at this level whose label starts with letter,
-- searching forward from the focused item and wrapping round.
function M.jump_to_letter(cursor, letter)
  local children = cursor.container.children
  local count = #children
  letter = letter:lower()
  for step = 1, count do
    local i = (cursor.index + step - 1) % count + 1
    if children[i].label:sub(1, 1):lower() == letter then
      cursor.index = i
      return true
    end
  end
  return false
end

-- Inserts node at the current level, right after the focused item
-- (or as the first item on the empty position), and focuses it.
-- Used by Control+N and Control+V. A node that is already placed is moved;
-- moving the focused node itself leaves it where it is. Returns nil,
-- changing nothing, if the node would end up inside itself.
function M.insert_after_focus(cursor, node)
  if node == M.focused(cursor) then return node end
  if M.contains(node, cursor.container) then return nil end
  if node.parent then
    local old_index = M.index_of(node)
    local same_level = node.parent == cursor.container
    M.detach(node)
    if same_level and old_index < cursor.index then
      cursor.index = cursor.index - 1
    end
  end
  M.add_child(cursor.container, node, cursor.index + 1)
  M.focus_node(cursor, node)
  return node
end

-- Removes the focused node and focuses the next item, else the previous,
-- else the empty position. Returns the removed node.
function M.remove_focused(cursor)
  local node = M.focused(cursor)
  if not node then return nil end
  M.detach(node)
  local count = #cursor.container.children
  if cursor.index > count then cursor.index = count end
  return node
end

return M
