-- Builds the spoken text for a tree item.
-- Plain Lua with no REAPER calls; parameter values come from a callback.

local M = {}

-- node: the focused node, or nil for the empty position.
-- with_state: true for Up, Down, Home, End and type-ahead; false for
--   Right and Left, which speak the item without its state.
-- value_of(node): returns the formatted value of a leaf (a parameter or
--   a setting).
function M.describe(node, with_state, value_of)
  if not node then return "empty" end

  if node.kind == "param" or node.kind == "setting" then
    local value = value_of and value_of(node) or ""
    if value == "" then return node.label end
    return node.label .. " " .. value
  end

  if with_state then return node.label .. " collapsed" end
  return node.label
end

return M
