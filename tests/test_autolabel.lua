local autolabel = require("autolabel")

local function words(label)
  return table.concat(autolabel.split_words(label), "|")
end

test("split on spaces, underscores and hyphens", function()
  check_equal(words("left Q attack"), "left|Q|attack")
  check_equal(words("L_Q-attack"), "L|Q|attack")
end)

test("split on case changes", function()
  check_equal(words("leftQAttack"), "left|Q|Attack")
  check_equal(words("LeftQAttack"), "Left|Q|Attack")
end)

test("split on letter and digit changes", function()
  check_equal(words("Band1Gain"), "Band|1|Gain")
end)

test("goal.md example: left Q attack under Q, attack", function()
  check_equal(autolabel.label("left Q attack", { "Q", "attack" }), "left")
  check_equal(autolabel.label("right Q attack", { "Q", "attack" }), "right")
end)

test("matching ignores case", function()
  check_equal(autolabel.label("Left Q Attack", { "q", "ATTACK" }), "Left")
end)

test("multi-word branch names contribute every word", function()
  check_equal(autolabel.label("Band 1 Gain", { "Band 1" }), "Gain")
end)

test("no match keeps the original exactly", function()
  check_equal(autolabel.label("Freq (Hz)", { "Mix" }), "Freq (Hz)")
end)

test("removing every word keeps the original", function()
  check_equal(autolabel.label("Q attack", { "Q", "attack" }), "Q attack")
end)

test("no branches keeps the original", function()
  check_equal(autolabel.label("left Q attack", {}), "left Q attack")
end)

test("abbreviations are not matched (known limit)", function()
  check_equal(autolabel.label("L Q Atk", { "attack" }), "L Q Atk")
end)
