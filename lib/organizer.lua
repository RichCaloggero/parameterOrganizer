-- The organized tree: tracks and effects mirrored from the source tree
-- (containers hold their effects, at any depth), with the user's branches
-- and parameters inside each effect. Plain Lua with no REAPER calls.
--
-- Inside an effect come, in order: the effects it holds (for a container),
-- the user's branches, then the default branch: the effect's unplaced
-- parameters, marked data.unplaced, as its view (fx_node.view) shows them.

local tree = require("tree")
local autolabel = require("autolabel")
local view = require("view")

local M = {}

local function mirror(source_node)
  return tree.new_node(source_node.kind, source_node.label, source_node.data)
end

local function find_by_guid(children, kind, guid)
  for _, child in ipairs(children) do
    if child.kind == kind and child.data.guid == guid then return child end
  end
  return nil
end

-- True for a parameter placed in this effect's part of the organized tree
-- (and not in an effect nested inside it, when this one is a container).
local function belongs_to(node, fx_node)
  return node.kind == "param" and node.data.fx_guid == fx_node.data.guid
    and not node.data.unplaced
end

-- Mirrors source_node's tracks and effects (recursively, for containers)
-- under org_node. Mirrored nodes come first, in the source's order; the
-- user's own items (branches and parameters) follow, in their own order.
local function sync_children(org_node, source_node)
  local old = org_node.children
  local user_items = {}
  for _, child in ipairs(old) do
    if child.kind == "branch" or child.kind == "param" then user_items[#user_items + 1] = child end
  end
  org_node.children = {}

  local params = {}
  for _, s in ipairs(source_node.children) do
    if s.kind == "track" or s.kind == "fx" then
      local n = find_by_guid(old, s.kind, s.data.guid) or mirror(s)
      n.label, n.data = s.label, s.data
      tree.add_child(org_node, n)
      sync_children(n, s)
    elseif s.kind == "param" then
      params[#params + 1] = s.data
    end
  end
  for _, item in ipairs(user_items) do tree.add_child(org_node, item) end

  if org_node.kind == "fx" then
    org_node.source_params = params
    org_node.view = org_node.view or { sorted = false }
    M.refresh_unplaced(org_node)
    -- The effect may have moved in the chain: its placed parameters follow.
    tree.walk(org_node, function(n)
      if belongs_to(n, org_node) then
        n.data.track, n.data.fx = org_node.data.track, org_node.data.fx
      end
    end)
  end
end

-- Rebuilds fx_node's default branch: every parameter of the effect that
-- isn't placed in a branch, filtered and sorted by fx_node.view.
-- A parameter placed directly in the effect (allowed before 0.9's single
-- tree) goes back to unplaced, since the default branch has no hand-made
-- order. Returns how many parameters the default branch shows.
function M.refresh_unplaced(fx_node)
  local kept = {}
  for _, child in ipairs(fx_node.children) do
    -- A missing parameter has no source to go back to, so it stays.
    if child.kind ~= "param" or (child.data.missing and not child.data.unplaced) then
      kept[#kept + 1] = child
    end
  end
  fx_node.children = {}
  for _, child in ipairs(kept) do tree.add_child(fx_node, child) end

  local placed = {}
  tree.walk(fx_node, function(n)
    if belongs_to(n, fx_node) and not n.data.missing then placed[n.data.index] = true end
  end)
  local unplaced = {}
  for _, p in ipairs(fx_node.source_params or {}) do
    if not placed[p.index] then unplaced[#unplaced + 1] = p end
  end

  local shown = view.apply(unplaced, fx_node.view or { sorted = false })
  for _, p in ipairs(shown) do
    local data = {}
    for k, v in pairs(p) do data[k] = v end
    data.unplaced = true
    tree.add_child(fx_node, tree.new_node("param", p.original_name, data))
  end
  return #shown
end

-- Brings the organized tree's tracks and effects (including effects inside
-- containers, at any depth) in line with the source tree: new ones are
-- added, missing ones removed, order and labels follow the source, and each
-- surviving effect keeps its branches. Pass nil to build a new tree.
function M.sync(organized_root, source_root)
  organized_root = organized_root or tree.new_node("root", "")
  sync_children(organized_root, source_root)
  return organized_root
end

-- Branches can be created only inside an effect: at the level of the
-- effect's contents, or deeper inside its branches.
function M.can_create_branch(cursor)
  local kind = cursor.container.kind
  return kind == "fx" or kind == "branch"
end

-- Only the user's items can be renamed, not the mirrored tracks and effects.
function M.can_rename(node)
  return node ~= nil and (node.kind == "branch" or node.kind == "param")
end

-- At an effect's own level, a new branch goes after the existing branches
-- (and, in a container, after the effects it holds), ahead of the
-- unplaced parameters. Inside a branch it goes after the focused item.
function M.create_branch(cursor, name)
  if cursor.container.kind == "fx" then
    local last = 0
    for i, child in ipairs(cursor.container.children) do
      if child.kind == "fx" or child.kind == "branch" then last = i end
    end
    cursor.index = last
  end
  return tree.insert_after_focus(cursor, tree.new_node("branch", name))
end

---------------------------------------------------------------------------
-- Parameters in the organized tree
--
-- A placed parameter's data copies the source parameter's (track, fx,
-- fx_guid, index, original_name) and may add user_label, set with F2.

-- Labels of the branches between the effect and the node, outermost first.
function M.branch_path(node)
  local path = {}
  local p = node.parent
  while p and p.kind == "branch" do
    table.insert(path, 1, p.label)
    p = p.parent
  end
  return path
end

-- The label a parameter shows: the user's own, or the autolabel.
function M.param_label(node)
  if node.data.user_label then return node.data.user_label end
  return autolabel.label(node.data.original_name, M.branch_path(node))
end

-- Recomputes the labels of all parameters under node, after a paste,
-- a move or a branch rename.
function M.refresh_labels(node)
  tree.walk(node, function(n)
    if n.kind == "param" then n.label = M.param_label(n) end
  end)
end

-- The placed copy of fx_node's parameter index, if any.
function M.find_placed(fx_node, index)
  return tree.walk(fx_node, function(n)
    return belongs_to(n, fx_node) and n.data.index == index and not n.data.missing
  end)
end

-- The organized effect node for an effect guid.
function M.find_fx(organized_root, fx_guid)
  return tree.walk(organized_root, function(n)
    return n.kind == "fx" and n.data.guid == fx_guid
  end)
end

-- Focuses fx_node's unplaced parameter with this index, if the view shows
-- it, else the first item at the effect's level.
local function focus_unplaced(cursor, fx_node, index)
  for i, child in ipairs(fx_node.children) do
    if child.data.unplaced and child.data.index == index then
      cursor.container, cursor.index = fx_node, i
      return child
    end
  end
  cursor.container, cursor.index = fx_node, #fx_node.children > 0 and 1 or 0
  return nil
end

-- Pasting at the effect's own level returns the parameter to unplaced.
-- Returns the node it lands on, if shown, and the branch path it left.
local function unplace(cursor, fx_node, data)
  local node = M.find_placed(fx_node, data.index)
  if not node then return nil, "Already unplaced" end
  local moved_from = M.branch_path(node)
  tree.detach(node)
  M.refresh_unplaced(fx_node)
  return focus_unplaced(cursor, fx_node, data.index), moved_from
end

-- Control+V: places the parameter whose data is given at the current
-- level, after the focused item. Each parameter appears only once, so one
-- that is already placed is moved. At the effect's own level it returns
-- the parameter to unplaced instead. Returns the placed node and, for a
-- move, the branch path it came from; or nil and a reason to speak.
function M.paste(cursor, data)
  if not M.can_create_branch(cursor) then return nil, "Not available here" end
  local fx_node = tree.enclosing(cursor.container, "fx")
  if fx_node.data.guid ~= data.fx_guid then
    return nil, "This parameter belongs to another effect"
  end
  if cursor.container == fx_node then return unplace(cursor, fx_node, data) end

  local node = M.find_placed(fx_node, data.index)
  local moved_from
  if node then
    moved_from = M.branch_path(node)
  else
    node = tree.new_node("param", "", {
      track = fx_node.data.track,
      fx = fx_node.data.fx,
      fx_guid = data.fx_guid,
      index = data.index,
      original_name = data.original_name,
    })
  end

  if not tree.insert_after_focus(cursor, node) then return nil, "Not available here" end
  node.label = M.param_label(node)
  -- The cursor is inside a branch, so rebuilding the effect's own level
  -- doesn't move it.
  M.refresh_unplaced(fx_node)
  return node, moved_from
end

-- F2 on a parameter: a name of its own, or "" to go back to the autolabel.
function M.rename_param(node, name)
  node.data.user_label = name ~= "" and name or nil
  node.label = M.param_label(node)
end

-- F2 on a branch: its parameters' autolabels follow the new name.
function M.rename_branch(node, name)
  node.label = name
  M.refresh_labels(node)
end

-- How many parameters a branch holds, at any depth.
function M.count_params(node)
  local count = 0
  tree.walk(node, function(n)
    if n.kind == "param" then count = count + 1 end
  end)
  return count
end

-- Delete: only the user's items can be removed.
M.can_delete = M.can_rename

return M
