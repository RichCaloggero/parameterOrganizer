-- The organized tree: tracks and effects mirrored from the source tree,
-- with the user's branches (and, from build step 6, parameters) inside
-- each effect. Plain Lua with no REAPER calls.

local tree = require("tree")

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

-- Brings the organized tree's track and effect levels in line with the
-- source tree: new tracks and effects are added, missing ones removed,
-- order and labels follow the source, and each surviving effect keeps
-- its branches. Pass nil to build a new organized tree.
function M.sync(organized_root, source_root)
  organized_root = organized_root or tree.new_node("root", "")
  local old_tracks = organized_root.children
  organized_root.children = {}

  for _, source_track in ipairs(source_root.children) do
    local track = find_by_guid(old_tracks, "track", source_track.data.guid) or mirror(source_track)
    track.label, track.data = source_track.label, source_track.data
    local old_fx = track.children
    track.children = {}
    tree.add_child(organized_root, track)

    for _, source_fx in ipairs(source_track.children) do
      local fx = find_by_guid(old_fx, "fx", source_fx.data.guid) or mirror(source_fx)
      fx.label, fx.data = source_fx.label, source_fx.data
      tree.add_child(track, fx)
    end
  end

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

function M.create_branch(cursor, name)
  return tree.insert_after_focus(cursor, tree.new_node("branch", name))
end

return M
