local value_search = require("value_search")

-- A frequency control from 20 Hz to 20 kHz, displayed like many plugins do.
local function frequency_at(x)
  local hz = 20 * 1000 ^ x
  if hz >= 1000 then return string.format("%.2f kHz", hz / 1000) end
  return string.format("%.1f Hz", hz)
end

-- A gain control from -inf to +12 dB, falling as x rises (unusual but legal).
local function falling_gain_at(x)
  if x >= 1 then return "-inf" end
  return string.format("%.1f dB", 12 - 60 * x)
end

local function shape_at(x)
  if x < 0.34 then return "Sine" elseif x < 0.67 then return "Square" end
  return "Saw"
end

test("parse numbers with units", function()
  check_equal(value_search.parse_number("350 Hz"), 350)
  check_equal(value_search.parse_number("2.50 kHz"), 2500)
  check_equal(value_search.parse_number("-6.0 dB"), -6)
  check_equal(value_search.parse_number("+3"), 3)
  check_equal(value_search.parse_number("-inf"), -math.huge)
  check_equal(value_search.parse_number("Sine"), nil)
end)

test("typed Hz finds the right frequency, shown in kHz", function()
  local x = value_search.find_normalized(2500, frequency_at)
  check_equal(frequency_at(x), "2.50 kHz")
end)

test("typed value below or above the range goes to the end", function()
  check_equal(value_search.find_normalized(5, frequency_at), 0)
  check_equal(value_search.find_normalized(50000, frequency_at), 1)
end)

test("a falling display is searched the other way", function()
  local x = value_search.find_normalized(-6, falling_gain_at)
  check_equal(falling_gain_at(x), "-6.0 dB")
end)

test("a display without numbers can't be searched by number", function()
  check_equal(value_search.find_normalized(3, shape_at), nil)
end)

-- A "reverb type" slider: five choices, each spanning a fifth of the range.
local TYPES = { "Concert Hall", "Bright Hall", "Plate", "Room", "Chamber" }
local function type_at(x)
  return TYPES[math.min(5, math.floor(x * 5) + 1)]
end

test("type slider: a small step moves to the next choice", function()
  local x = value_search.step_until_changed(0.0, 1, 0.01, type_at)
  check_equal(type_at(x), "Bright Hall")
  x = value_search.step_until_changed(x, 1, 0.01, type_at)
  check_equal(type_at(x), "Plate")
  x = value_search.step_until_changed(x, -1, 0.01, type_at)
  check_equal(type_at(x), "Bright Hall")
end)

test("type slider: stepping past the last choice changes nothing", function()
  check_equal(value_search.step_until_changed(0.9, 1, 0.01, type_at), false)
  check_equal(value_search.step_until_changed(0.1, -1, 0.1, type_at), false)
end)

test("type slider: the last choice can sit only at the very end", function()
  local function edge_at(x) return x >= 1 and "Max" or "Normal" end
  check_equal(value_search.step_until_changed(0.5, 1, 0.01, edge_at), 1)
end)

test("a step that already changes the display is used as is", function()
  check_equal(value_search.step_until_changed(0.5, 1, 0.01, frequency_at), 0.51)
end)

test("no display from the plugin: nil, so the caller takes a plain step", function()
  check_equal(value_search.step_until_changed(0.5, 1, 0.01, function() return nil end), nil)
end)

test("words match the display text, ignoring case", function()
  local x = value_search.find_by_text(" square ", shape_at)
  check_equal(shape_at(x), "Square")
  check_equal(value_search.find_by_text("Triangle", shape_at), nil)
end)
