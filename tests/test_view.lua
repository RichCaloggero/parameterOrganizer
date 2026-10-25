local view = require("view")

local function sorted(names)
  local params = {}
  for i, name in ipairs(names) do params[i] = { original_name = name } end
  local result = {}
  for i, p in ipairs(view.apply(params, { sorted = true })) do result[i] = p.original_name end
  return table.concat(result, ", ")
end

test("natural order puts numbers in numeric order", function()
  check_equal(sorted({ "band10", "band2", "band1" }), "band1, band2, band10")
  check_equal(sorted({ "Band 10 Gain", "Band 2 Gain", "Band 1 Q" }), "Band 1 Q, Band 2 Gain, Band 10 Gain")
end)

test("natural order ignores case", function()
  check_equal(sorted({ "b", "A", "a2", "B1" }), "A, a2, b, B1")
end)

test("names that compare equal keep their source order", function()
  check_equal(sorted({ "band01", "Band1", "band1" }), "band01, Band1, band1")
end)

test("very long numbers compare correctly", function()
  check_equal(sorted({ "x99999999999999999999", "x100000000000000000000", "x2" }),
    "x2, x99999999999999999999, x100000000000000000000")
end)

test("filter folds case and spaces, and matches what is typed", function()
  check_equal(view.matches("Band 1  Low   Gain", "low gain"), true)
  check_equal(view.matches("Band 1 Low Gain", "  LOW  GAIN "), true)
  check_equal(view.matches("Band 1 Gain", "band gain"), false, "words must be adjacent")
  check_equal(view.matches("Gain (dB)", "(db"), true, "pattern characters are literal")
  check_equal(view.matches("Mix 50%", "%"), true)
end)

test("filter and sort together", function()
  local params = {
    { original_name = "Band 10 Gain" }, { original_name = "Band 2 Freq" },
    { original_name = "Band 2 Gain" }, { original_name = "Output" },
  }
  local shown = view.apply(params, { sorted = true, filter = "gain" })
  check_equal(#shown, 2)
  check_equal(shown[1].original_name, "Band 2 Gain")
  check_equal(shown[2].original_name, "Band 10 Gain")
end)
