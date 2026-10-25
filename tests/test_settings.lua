local settings_lib = require("settings")
local tree = require("tree")
local announce = require("announce")

local function memory_store()
  local saved = {}
  return { get = function(k) return saved[k] end, set = function(k, v) saved[k] = v end }, saved
end

test("settings start at their defaults", function()
  local s = settings_lib.new(memory_store())
  check_equal(s.get("swap_home_end"), true)
  check_equal(s.value_text("swap_home_end"), "swapped, Home goes down")
end)

test("stepping a switch turns it off and on, and is saved", function()
  local store, saved = memory_store()
  local s = settings_lib.new(store)
  s.step("swap_home_end", -1)
  check_equal(s.get("swap_home_end"), false)
  check_equal(saved.swap_home_end, "0", "stored")
  check_equal(s.value_text("swap_home_end"), "standard, Home goes up")
  s.step("swap_home_end", 1)
  check_equal(s.get("swap_home_end"), true)
end)

test("a saved value is read back by a new session", function()
  local store = memory_store()
  settings_lib.new(store).set("swap_home_end", false)
  check_equal(settings_lib.new(store).get("swap_home_end"), false)
end)

test("a setting is a leaf that speaks its value", function()
  local node = tree.new_node("setting", "Home and End", { key = "swap_home_end" })
  check_equal(tree.is_leaf(node), true)
  check_equal(announce.describe(node, true, function() return "standard" end), "Home and End standard")
end)
