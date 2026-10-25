local tree = require("tree")
local announce = require("announce")

local function value_of() return "350 Hz" end

test("branches say collapsed only when asked for state", function()
  local node = tree.new_node("branch", "frequency")
  check_equal(announce.describe(node, true, value_of), "frequency collapsed")
  check_equal(announce.describe(node, false, value_of), "frequency")
end)

test("parameters speak their value, never a state", function()
  local node = tree.new_node("param", "left")
  check_equal(announce.describe(node, true, value_of), "left 350 Hz")
  check_equal(announce.describe(node, false, value_of), "left 350 Hz")
end)

test("a parameter with no value speaks just its label", function()
  local node = tree.new_node("param", "left")
  check_equal(announce.describe(node, true, function() return "" end), "left")
end)

test("a container says so after its name", function()
  local node = tree.new_node("fx", "Chain", { is_container = true })
  check_equal(announce.describe(node, true, value_of), "Chain container collapsed")
  check_equal(announce.describe(node, false, value_of), "Chain container")
  check_equal(announce.describe(tree.new_node("fx", "Phaser", {}), false, value_of), "Phaser")
end)

test("the empty position says empty", function()
  check_equal(announce.describe(nil, true, value_of), "empty")
end)
