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

---------------------------------------------------------------------------
-- Multiselect mode

-- An effect with branch a holding p and q, then parameters x, y, z.
local function effect()
  local fx = tree.new_node("fx", "EQ")
  local a = tree.add_child(fx, tree.new_node("branch", "a"))
  for _, name in ipairs({ "p", "q" }) do tree.add_child(a, tree.new_node("param", name)) end
  for _, name in ipairs({ "x", "y", "z" }) do tree.add_child(fx, tree.new_node("param", name)) end
  return fx, a
end

test("multiselect: the selection spans levels within an effect, in tree order", function()
  local fx, a = effect()
  local sel = selection.new()
  sel.sticky = true
  selection.toggle(sel, { container = fx, index = 3 })   -- y
  selection.toggle(sel, { container = a, index = 2 })    -- q
  check_equal(labels(sel), "q y")
end)

test("multiselect: ranges and Control+A add to the selection", function()
  local fx, a = effect()
  local sel = selection.new()
  sel.sticky = true
  selection.toggle(sel, { container = a, index = 1 })    -- p
  local c = { container = fx, index = 2 }               -- x
  tree.move_next(c)
  selection.extend(sel, c, 2)
  check_equal(labels(sel), "p x y")
  tree.move_prev(c)
  selection.extend(sel, c, 3)
  check_equal(labels(sel), "p x", "the range shrinks, the earlier pick stays")
  selection.select_leaves(sel, c)
  check_equal(labels(sel), "p x y z")
end)

test("multiselect: moving to another effect starts afresh", function()
  local fx = effect()
  local other = effect()
  local sel = selection.new()
  sel.sticky = true
  selection.toggle(sel, { container = fx, index = 2 })
  selection.toggle(sel, { container = other, index = 3 })
  check_equal(labels(sel), "y")
  check_equal(selection.nodes(sel)[1].parent, other)
end)

test("update drops nodes no longer in the tree and follows replacements", function()
  local fx = effect()
  local sel = selection.new()
  sel.sticky = true
  local c = { container = fx, index = 2 }
  selection.select_leaves(sel, c)                       -- x y z
  local x, y = fx.children[2], fx.children[3]
  local new_x = tree.new_node("param", "x")
  fx.children = { fx.children[1], new_x }               -- rebuilt: y and z gone
  new_x.parent = fx
  selection.update(sel, function(n) if n == x then return new_x end end)
  check_equal(labels(sel), "x")
  check_equal(selection.is_selected(sel, new_x), true)
  check_equal(selection.is_selected(sel, y), false)
end)
