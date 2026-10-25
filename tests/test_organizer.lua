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

---------------------------------------------------------------------------
-- Parameters (build step 6)

-- One effect with branches Q > attack, ready for pasting.
local function phaser_with_branches()
  local organized = organizer.sync(nil, source(PROJECT))
  local c = tree.new_cursor(organized)
  tree.enter(c)
  tree.enter(c)
  organizer.create_branch(c, "Q")
  tree.enter(c)
  organizer.create_branch(c, "attack")
  tree.enter(c)
  return organized, c
end

local function param_data(index, name, fx_guid)
  return { fx_guid = fx_guid or "F1", index = index, original_name = name }
end

test("paste places a parameter with its autolabel", function()
  local organized, c = phaser_with_branches()
  local node, moved = organizer.paste(c, param_data(4, "left Q attack"))
  check_equal(node.label, "left")
  check_equal(moved, nil, "not a move")
  check_equal(tree.focused(c), node, "focused")
  check_equal(outline(organized), "Track 1(Phaser(Q(attack(left))) EQ) Track 2(Verb)")
end)

test("paste is refused outside an effect and in another effect", function()
  local organized = organizer.sync(nil, source(PROJECT))
  local c = tree.new_cursor(organized)
  check_equal(select(2, organizer.paste(c, param_data(0, "Gain"))), "Not available here")
  tree.enter(c)
  tree.move_next(c)
  tree.enter(c)   -- inside EQ
  check_equal(select(2, organizer.paste(c, param_data(0, "Gain", "F1"))),
    "This parameter belongs to another effect")
end)

test("pasting a placed parameter again moves it and reports where from", function()
  local organized, c = phaser_with_branches()
  organizer.paste(c, param_data(4, "left Q attack"))
  tree.leave(c)
  tree.leave(c)   -- back at the Phaser's contents, focus on Q
  local node, moved = organizer.paste(c, param_data(4, "left Q attack"))
  check_equal(table.concat(moved, ", "), "Q, attack")
  check_equal(node.label, "left Q attack", "no branches above any more")
  check_equal(outline(organized), "Track 1(Phaser(Q(attack) left Q attack) EQ) Track 2(Verb)")
end)

test("renaming a branch relabels the parameters inside", function()
  local _, c = phaser_with_branches()
  local node = organizer.paste(c, param_data(4, "left Q attack"))
  organizer.rename_branch(node.parent, "release")
  check_equal(node.label, "left attack")
end)

test("a parameter's own name, and back to the autolabel", function()
  local _, c = phaser_with_branches()
  local node = organizer.paste(c, param_data(4, "left Q attack"))
  organizer.rename_param(node, "L")
  check_equal(node.label, "L")
  organizer.rename_branch(node.parent, "release")
  check_equal(node.label, "L", "own name survives a branch rename")
  organizer.rename_param(node, "")
  check_equal(node.label, "left attack", "autolabel again")
end)

test("counting a branch's parameters at any depth", function()
  local organized, c = phaser_with_branches()
  organizer.paste(c, param_data(4, "left Q attack"))
  organizer.paste(c, param_data(5, "right Q attack"))
  local q = organized.children[1].children[1].children[1]
  check_equal(organizer.count_params(q), 2)
end)

test("sync moves placed parameters along with their effect", function()
  local organized, c = phaser_with_branches()
  local node = organizer.paste(c, param_data(4, "left Q attack"))
  local moved = source(PROJECT)
  moved.children[1].children[1].data.fx = 3
  organizer.sync(organized, moved)
  check_equal(node.data.fx, 3)
end)

---------------------------------------------------------------------------
-- Containers

-- Track > Container(ReaEQ(Gain), Inner(ReaComp(Ratio), Bypass), Bypass)
local function container_source()
  local root = tree.new_node("root", "")
  local track = tree.add_child(root, tree.new_node("track", "Bus", { guid = "T" }))
  local c1 = tree.add_child(track, tree.new_node("fx", "Container", { guid = "C1", fx = 0 }))
  local eq = tree.add_child(c1, tree.new_node("fx", "ReaEQ", { guid = "EQ", fx = 100 }))
  tree.add_child(eq, tree.new_node("param", "Gain", { fx_guid = "EQ", index = 0 }))
  local c2 = tree.add_child(c1, tree.new_node("fx", "Inner", { guid = "C2", fx = 101 }))
  local comp = tree.add_child(c2, tree.new_node("fx", "ReaComp", { guid = "COMP", fx = 200 }))
  tree.add_child(comp, tree.new_node("param", "Ratio", { fx_guid = "COMP", index = 0 }))
  tree.add_child(c2, tree.new_node("param", "Bypass", { fx_guid = "C2", index = 0 }))
  tree.add_child(c1, tree.new_node("param", "Bypass", { fx_guid = "C1", index = 0 }))
  return root
end

test("containers are mirrored with their effects, at any depth", function()
  local organized = organizer.sync(nil, container_source())
  check_equal(outline(organized), "Bus(Container(ReaEQ Inner(ReaComp)))")
end)

test("a container's own parameter and its effects' parameters stay apart", function()
  local organized = organizer.sync(nil, container_source())
  local c = tree.new_cursor(organized)
  tree.enter(c)            -- Container
  tree.enter(c)            -- inside: ReaEQ
  tree.move_next(c)        -- Inner
  tree.enter(c)            -- inside Inner: ReaComp
  tree.enter(c)            -- inside ReaComp: empty
  organizer.paste(c, { fx_guid = "COMP", index = 0, original_name = "Ratio" })
  tree.leave(c)            -- ReaComp, inside Inner
  -- Inner's own Bypass has the same index as ReaComp's Ratio: not confused.
  local node, moved = organizer.paste(c, { fx_guid = "C2", index = 0, original_name = "Bypass" })
  check_equal(moved, nil, "a new placement, not a move")
  check_equal(outline(organized), "Bus(Container(ReaEQ Inner(ReaComp(Ratio) Bypass)))")
  check_equal(node.parent.label, "Inner")
end)

test("in a container, new items go after its effects", function()
  local organized = organizer.sync(nil, container_source())
  local c = tree.new_cursor(organized)
  tree.enter(c)
  tree.enter(c)            -- focus on ReaEQ, the first effect in the container
  organizer.create_branch(c, "mix")
  check_equal(outline(organized), "Bus(Container(ReaEQ Inner(ReaComp) mix))")
end)

test("sync keeps a container's branches after its effects", function()
  local organized = organizer.sync(nil, container_source())
  local container = organized.children[1].children[1]
  tree.add_child(container, tree.new_node("branch", "mix"))
  organizer.sync(organized, container_source())
  check_equal(outline(organized), "Bus(Container(ReaEQ Inner(ReaComp) mix))")
end)
