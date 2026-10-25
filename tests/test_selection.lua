local tree = require("tree")
local selection = require("selection")

-- An effect level: branches a and b, then parameters x, y, z.
local function level()
  local fx = tree.new_node("fx", "EQ")
  for _, name in ipairs({ "a", "b" }) do tree.add_child(fx, tree.new_node("branch", name)) end
  for _, name in ipairs({ "x", "y", "z" }) do tree.add_child(fx, tree.new_node("param", name)) end
  return fx
end

local function labels(sel)
  local list = {}
  for i, node in ipairs(selection.nodes(sel)) do list[i] = node.label end
  return table.concat(list, " ")
end

test("Shift+arrows select a range from the anchor, in either direction", function()
  local c, sel = { container = level(), index = 3 }, selection.new()
  tree.move_next(c)
  selection.extend(sel, c, 3)
  tree.move_next(c)
  selection.extend(sel, c, 4)
  check_equal(labels(sel), "x y z")
  tree.move_prev(c)
  selection.extend(sel, c, 5)
  check_equal(labels(sel), "x y", "shrinks back towards the anchor")
  tree.move_prev(c)
  tree.move_prev(c)
  selection.extend(sel, c, 4)
  check_equal(labels(sel), "b x", "past the anchor the other way")
end)

test("Shift+Space toggles, and becomes the anchor for the next range", function()
  local c, sel = { container = level(), index = 1 }, selection.new()
  check_equal(selection.toggle(sel, c), true)
  c.index = 4
  selection.toggle(sel, c)
  check_equal(labels(sel), "a y")
  check_equal(selection.toggle(sel, c), false, "toggled off")
  check_equal(labels(sel), "a")
  tree.move_next(c)
  selection.extend(sel, c, 4)
  check_equal(labels(sel), "y z", "a range from the new anchor replaces the rest")
end)

test("Control+A selects every leaf at the level, skipping branches", function()
  local c, sel = { container = level(), index = 1 }, selection.new()
  check_equal(selection.select_leaves(sel, c), 3)
  check_equal(labels(sel), "x y z")
end)

test("a selection belongs to one level", function()
  local fx = level()
  local c, sel = { container = fx, index = 3 }, selection.new()
  selection.toggle(sel, c)
  local other = { container = fx.children[1], index = 0 }
  tree.add_child(fx.children[1], tree.new_node("param", "inner"))
  other.index = 1
  selection.toggle(sel, other)
  check_equal(labels(sel), "inner")
  check_equal(selection.is_selected(sel, fx.children[3]), false)
end)

test("clearing", function()
  local c, sel = { container = level(), index = 3 }, selection.new()
  selection.select_leaves(sel, c)
  selection.clear(sel)
  check_equal(selection.count(sel), 0)
  check_equal(labels(sel), "")
end)
