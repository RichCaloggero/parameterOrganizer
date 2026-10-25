local tree = require("tree")
local organizer = require("organizer")
local layout = require("layout")
local storage = require("storage")

-- An organized effect with: Q > attack > left (own name "L") and right,
-- then Out > Mix.
local function organized_phaser()
  local fx = tree.new_node("fx", "Phaser", { guid = "F1", plugin_key = "JS: phaser", track = "t", fx = 0 })
  local c = tree.new_cursor(fx)
  organizer.create_branch(c, "Q")
  tree.enter(c)
  organizer.create_branch(c, "attack")
  tree.enter(c)
  local left = organizer.paste(c, { fx_guid = "F1", index = 0, original_name = "left Q attack" })
  organizer.rename_param(left, "L")
  organizer.paste(c, { fx_guid = "F1", index = 1, original_name = "right Q attack" })
  tree.leave(c)
  tree.leave(c)
  organizer.create_branch(c, "Out")
  tree.enter(c)
  organizer.paste(c, { fx_guid = "F1", index = 2, original_name = "Mix" })
  return fx
end

local function outline(node)
  local parts = {}
  for _, child in ipairs(node.children) do
    local inner = #child.children > 0 and "(" .. outline(child) .. ")" or ""
    local mark = child.data.missing and "!" or ""
    parts[#parts + 1] = child.label .. mark .. inner
  end
  return table.concat(parts, " ")
end

local NAMES = { [0] = "left Q attack", [1] = "right Q attack", [2] = "Mix" }

test("a layout saves and loads back the same tree", function()
  local text = layout.serialize(organized_phaser())
  local other = tree.new_node("fx", "Phaser", { guid = "F2", track = "t2", fx = 5 })
  check_equal(layout.apply(other, text, NAMES), true)
  check_equal(outline(other), "Q(attack(L right)) Out(Mix)")
end)

test("loaded parameters belong to the instance they are loaded into", function()
  local text = layout.serialize(organized_phaser())
  local other = tree.new_node("fx", "Phaser", { guid = "F2", track = "t2", fx = 5 })
  layout.apply(other, text, NAMES)
  local right = other.children[1].children[1].children[2]
  check_equal(right.data.fx_guid, "F2")
  check_equal(right.data.track, "t2")
  check_equal(right.data.fx, 5)
  check_equal(right.data.index, 1)
  check_equal(organizer.find_placed(other, 1), right, "found as placed")
end)

test("a reordered plugin: parameters are found again by name", function()
  local text = layout.serialize(organized_phaser())
  local other = tree.new_node("fx", "Phaser", { guid = "F2" })
  layout.apply(other, text, { [0] = "Mix", [1] = "left Q attack", [2] = "right Q attack" })
  check_equal(outline(other), "Q(attack(L right)) Out(Mix)")
  check_equal(other.children[1].children[1].children[1].data.index, 1, "left moved to 1")
  check_equal(other.children[2].children[1].data.index, 0, "Mix moved to 0")
end)

test("a parameter the plugin no longer has is kept, marked missing", function()
  local text = layout.serialize(organized_phaser())
  local other = tree.new_node("fx", "Phaser", { guid = "F2" })
  layout.apply(other, text, { [0] = "left Q attack", [1] = "right Q attack" })
  check_equal(outline(other), "Q(attack(L right)) Out(Mix!)")
  check_equal(organizer.find_placed(other, 2), nil, "a missing parameter doesn't count as placed")
  -- Saving again keeps it, so the layout isn't lost.
  check_equal(layout.serialize(other):find("Mix", 1, true) ~= nil, true)
end)

test("names with tabs or line breaks are saved safely", function()
  local fx = tree.new_node("fx", "Phaser", { guid = "F1" })
  local c = tree.new_cursor(fx)
  organizer.create_branch(c, "odd\tname\nhere")
  local other = tree.new_node("fx", "Phaser", { guid = "F2" })
  layout.apply(other, layout.serialize(fx), {})
  check_equal(other.children[1].label, "odd name here")
end)

test("a container keeps the effects it holds when its layout loads", function()
  local container = tree.new_node("fx", "Container", { guid = "C1", is_container = true })
  tree.add_child(container, tree.new_node("fx", "ReaEQ", { guid = "EQ" }))
  local c = tree.new_cursor(container)
  organizer.create_branch(c, "mix")
  local text = layout.serialize(container)
  check_equal(text:find("ReaEQ", 1, true), nil, "held effects aren't part of its layout")
  layout.apply(container, text, {})
  check_equal(outline(container), "ReaEQ mix")
end)

test("text that isn't a layout changes nothing", function()
  local fx = organized_phaser()
  check_equal(layout.apply(fx, "something else\n", NAMES), false)
  check_equal(outline(fx), "Q(attack(L right)) Out(Mix)")
end)

test("a 0.9 layout's parameters placed directly in the effect become unplaced", function()
  local text = "ParameterOrganizer layout 1\nplugin\tJS: phaser\n" ..
    "B\t0\tQ\nP\t1\t0\tleft Q attack\t\nP\t0\t2\tMix\t\nP\t0\t7\tGone\t\n"
  local fx = tree.new_node("fx", "Phaser", { guid = "F2" })
  fx.source_params = {
    { fx_guid = "F2", index = 0, original_name = "left Q attack" },
    { fx_guid = "F2", index = 1, original_name = "right Q attack" },
    { fx_guid = "F2", index = 2, original_name = "Mix" },
  }
  layout.apply(fx, text, NAMES)
  -- Gone is missing, so it stays where it was saved.
  check_equal(outline(fx), "Q(left attack) Gone! right Q attack Mix")
  check_equal(layout.serialize(fx):find("Mix", 1, true), nil, "Mix no longer saved")
end)

test("layout file names are safe and distinct", function()
  local a = storage.file_name("C:\\Plugins\\Valhalla Vintage Verb.vst3")
  check_equal(a:match("^[%w%-%._]+$") ~= nil, true, "safe characters only")
  check_equal(a ~= storage.file_name("C:/Plugins/Valhalla Vintage Verb.vst3"), true, "distinct")
end)
