local tree = require("tree")
local organizer = require("organizer")

-- A source tree: tracks and effects identified by guid, with parameters.
local function source(spec)
  local root = tree.new_node("root", "")
  for _, t in ipairs(spec) do
    local track = tree.add_child(root, tree.new_node("track", t.label, { guid = t.guid }))
    for _, f in ipairs(t.fx) do
      local fx = tree.add_child(track, tree.new_node("fx", f.label, { guid = f.guid }))
      tree.add_child(fx, tree.new_node("param", "Gain", { index = 0 }))
    end
  end
  return root
end

local function outline(node)
  local parts = {}
  for _, child in ipairs(node.children) do
    local inner = #child.children > 0 and "(" .. outline(child) .. ")" or ""
    parts[#parts + 1] = child.label .. inner
  end
  return table.concat(parts, " ")
end

local PROJECT = {
  { label = "Track 1", guid = "T1", fx = { { label = "Phaser", guid = "F1" }, { label = "EQ", guid = "F2" } } },
  { label = "Track 2", guid = "T2", fx = { { label = "Verb", guid = "F3" } } },
}

test("organized tree mirrors tracks and effects, without parameters", function()
  local organized = organizer.sync(nil, source(PROJECT))
  check_equal(outline(organized), "Track 1(Phaser EQ) Track 2(Verb)")
end)

test("branches only inside an effect", function()
  local organized = organizer.sync(nil, source(PROJECT))
  local c = tree.new_cursor(organized)
  check_equal(organizer.can_create_branch(c), false, "track level")
  tree.enter(c)
  check_equal(organizer.can_create_branch(c), false, "effect level")
  tree.enter(c)
  check_equal(organizer.can_create_branch(c), true, "inside an effect")
end)

test("creating branches inside an empty effect, then beside each other", function()
  local organized = organizer.sync(nil, source(PROJECT))
  local c = tree.new_cursor(organized)
  tree.enter(c)
  tree.enter(c)
  organizer.create_branch(c, "frequency")
  organizer.create_branch(c, "Q")
  check_equal(outline(organized), "Track 1(Phaser(frequency Q) EQ) Track 2(Verb)")
  check_equal(tree.focused(c).label, "Q")
end)

test("nested branches", function()
  local organized = organizer.sync(nil, source(PROJECT))
  local c = tree.new_cursor(organized)
  tree.enter(c)
  tree.enter(c)
  organizer.create_branch(c, "frequency")
  tree.enter(c)
  check_equal(organizer.can_create_branch(c), true, "inside a branch")
  organizer.create_branch(c, "min")
  check_equal(outline(organized), "Track 1(Phaser(frequency(min)) EQ) Track 2(Verb)")
end)

test("only branches and parameters can be renamed", function()
  check_equal(organizer.can_rename(tree.new_node("branch", "x")), true)
  check_equal(organizer.can_rename(tree.new_node("param", "x")), true)
  check_equal(organizer.can_rename(tree.new_node("fx", "x")), false)
  check_equal(organizer.can_rename(tree.new_node("track", "x")), false)
  check_equal(organizer.can_rename(nil), false, "empty position")
end)

test("sync keeps branches, follows renames and order, adds and removes", function()
  local organized = organizer.sync(nil, source(PROJECT))
  local phaser = organized.children[1].children[1]
  tree.add_child(phaser, tree.new_node("branch", "frequency"))

  local changed = source({
    { label = "Track 2 Drums", guid = "T2", fx = { { label = "Verb", guid = "F3" } } },
    { label = "Track 1", guid = "T1", fx = { { label = "Phaser", guid = "F1" }, { label = "Comp", guid = "F4" } } },
  })
  organizer.sync(organized, changed)

  check_equal(outline(organized), "Track 2 Drums(Verb) Track 1(Phaser(frequency) Comp)")
  check_equal(organized.children[2].children[1], phaser, "same phaser node kept")
  check_equal(phaser.parent, organized.children[2], "parent link")
end)
