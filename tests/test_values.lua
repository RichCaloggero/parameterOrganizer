-- Tests value changes in reaper_fx against a small fake of the REAPER API.

local reaper_fx = require("reaper_fx")
local tree = require("tree")

-- One fake parameter; kind is "continuous", "stepped", "toggle", etc.
local param

-- Five reverb types, each spanning a fifth of the range.
local TYPES = { "Concert Hall", "Bright Hall", "Plate", "Room", "Chamber" }
local function type_at(x)
  return TYPES[math.min(5, math.floor(x * 5) + 1)]
end
-- Three choices, the middle one only 0.002 wide.
local function narrow_at(x)
  if x < 0.5 then return "Small" end
  if x < 0.502 then return "Medium" end
  return "Large"
end

local function fake(kind, normalized)
  param = { kind = kind, normalized = normalized, set_calls = 0, last_asked = normalized }
end

-- Stepped: values 0 to 4 in steps of 1, large step 2.
-- Range 100: values 0 to 100 in steps of 1, no large step reported.
-- Mode: three choices, 0 to 2 in steps of 1, no large step reported.
local MAX = { stepped = 4, range100 = 100, mode = 2 }
local LARGE = { stepped = 2, range100 = 0, mode = 0 }

reaper = {
  TrackFX_GetParameterStepSizes = function()
    if MAX[param.kind] then return true, 1, 0, LARGE[param.kind], false end
    if param.kind == "toggle" then return true, 0, 0, 0, true end
    return false, 0, 0, 0, false
  end,
  TrackFX_GetParamEx = function()
    local max = MAX[param.kind] or 1
    return param.normalized * max, 0, max, max / 2
  end,
  TrackFX_SetParam = function(_, _, _, value)
    local max = MAX[param.kind] or 1
    param.normalized = value / max
    param.set_calls = param.set_calls + 1
  end,
  TrackFX_GetParamNormalized = function() return param.normalized end,
  TrackFX_SetParamNormalized = function(_, _, _, x)
    param.normalized = x
    param.set_calls = param.set_calls + 1
  end,
  TrackFX_FormatParamValueNormalized = function(_, _, _, x)
    if param.kind == "no_format" then return false, "" end
    -- Like ValhallaVintageVerb: ignores x and describes the current setting.
    if param.kind == "ignores_x" then return true, type_at(param.normalized) end
    if param.kind == "narrow" then return true, narrow_at(x) end
    -- Answers the question before this one, so 0 and 1 still differ.
    if param.kind == "answers_late" then
      local asked = param.last_asked
      param.last_asked = x
      return true, type_at(asked)
    end
    return true, string.format("%.1f dB", -60 + 72 * x)
  end,
  TrackFX_GetFormattedParamValue = function()
    if param.kind == "no_format" then return false, "" end
    if param.kind == "ignores_x" or param.kind == "answers_late" then
      return true, type_at(param.normalized)
    end
    if param.kind == "narrow" then return true, narrow_at(param.normalized) end
    -- Answers questions exactly, but really snaps to steps of 0.02.
    if param.kind == "snaps" then
      local snapped = math.floor(param.normalized / 0.02 + 1e-9) * 0.02
      return true, string.format("%.1f dB", -60 + 72 * snapped)
    end
    return true, string.format("%.1f dB", -60 + 72 * param.normalized)
  end,
}

local node = tree.new_node("param", "Gain", { track = {}, fx = 0, index = 0 })

local function near(a, b) return math.abs(a - b) < 1e-9 end

test("continuous: small and large steps", function()
  fake("continuous", 0.5)
  reaper_fx.step_value(node, 1, false)
  check_equal(near(param.normalized, 0.51), true, "small up")
  reaper_fx.step_value(node, -1, true)
  check_equal(near(param.normalized, 0.41), true, "large down")
end)

test("continuous: steps stop at the ends", function()
  fake("continuous", 0.95)
  reaper_fx.step_value(node, 1, true)
  check_equal(param.normalized, 1, "top")
  fake("continuous", 0.005)
  reaper_fx.step_value(node, -1, false)
  check_equal(param.normalized, 0, "bottom")
end)

test("stepped: one position, or the plugin's large step", function()
  fake("stepped", 0.25)
  reaper_fx.step_value(node, 1, false)
  check_equal(param.normalized, 0.5, "one up")
  reaper_fx.step_value(node, 1, true)
  check_equal(param.normalized, 1, "large up")
  reaper_fx.step_value(node, 1, true)
  check_equal(param.normalized, 1, "stays at top")
end)

test("stepped without a large step: Page keys move 10% of the range", function()
  fake("range100", 0.5)
  reaper_fx.step_value(node, 1, true)
  check_equal(near(param.normalized, 0.6), true, "50 to 60")
  reaper_fx.step_value(node, 1, false)
  check_equal(near(param.normalized, 0.61), true, "60 to 61")
end)

test("stepped with few choices: Page keys still move one choice", function()
  fake("mode", 0)
  reaper_fx.step_value(node, 1, true)
  check_equal(param.normalized, 0.5, "first to second")
end)

test("toggle: up turns on, down turns off", function()
  fake("toggle", 0)
  reaper_fx.step_value(node, 1, false)
  check_equal(param.normalized, 1, "on")
  reaper_fx.step_value(node, -1, true)
  check_equal(param.normalized, 0, "off")
end)

test("REAPER's Bypass and Delta switch fully on and off", function()
  local switch = tree.new_node("param", "Bypass", { track = {}, fx = 0, index = 18, builtin_switch = true })
  fake("continuous", 0)
  reaper_fx.step_value(switch, 1, false)
  check_equal(param.normalized, 1, "on with a small step")
  reaper_fx.step_value(switch, -1, true)
  check_equal(param.normalized, 0, "off with a large step")
end)

test("start and end of the range", function()
  fake("continuous", 0.4)
  reaper_fx.set_extreme(node, true)
  check_equal(param.normalized, 1, "end")
  reaper_fx.set_extreme(node, false)
  check_equal(param.normalized, 0, "start")
end)

test("typed value in the plugin's units", function()
  fake("continuous", 0)
  check_equal(reaper_fx.set_value_from_text(node, "-6"), true)
  local _, shown = reaper.TrackFX_FormatParamValueNormalized(nil, 0, 0, param.normalized, "")
  check_equal(shown, "-6.0 dB")
end)

test("typed number is a percentage when the plugin can't format", function()
  fake("no_format", 0)
  check_equal(reaper_fx.set_value_from_text(node, "40"), true)
  check_equal(near(param.normalized, 0.4), true, "40 percent")
end)

test("typed word that matches nothing changes nothing", function()
  fake("continuous", 0.3)
  check_equal(reaper_fx.set_value_from_text(node, "loud"), false)
  check_equal(param.normalized, 0.3, "unchanged")
end)

test("plugin that ignores the question: steps still find the next choice", function()
  fake("ignores_x", 0.1)
  reaper_fx.step_value(node, 1, false)
  check_equal(type_at(param.normalized), "Bright Hall", "next")
  reaper_fx.step_value(node, -1, false)
  check_equal(type_at(param.normalized), "Concert Hall", "back")
end)

test("plugin that ignores the question: no next choice restores the value", function()
  fake("ignores_x", 0.9)
  reaper_fx.step_value(node, 1, false)
  check_equal(param.normalized, 0.9, "restored")
end)

test("plugin that ignores the question: typed word still works", function()
  fake("ignores_x", 0.1)
  check_equal(reaper_fx.set_value_from_text(node, "room"), true)
  check_equal(type_at(param.normalized), "Room")
  check_equal(reaper_fx.set_value_from_text(node, "spring"), false)
  check_equal(type_at(param.normalized), "Room", "unchanged after no match")
end)

test("plugin that answers the previous question: steps still find the next choice", function()
  fake("answers_late", 0.1)
  param.last_asked = 0.9
  reaper_fx.step_value(node, 1, false)
  check_equal(type_at(param.normalized), "Bright Hall", "next")
  reaper_fx.step_value(node, -1, false)
  check_equal(type_at(param.normalized), "Concert Hall", "back")
end)

test("plugin whose real display differs from its answers: one press still changes it", function()
  fake("snaps", 0.5)
  local _, before = reaper.TrackFX_GetFormattedParamValue()
  reaper_fx.step_value(node, 1, false)
  local _, after = reaper.TrackFX_GetFormattedParamValue()
  check_equal(after ~= before, true, "changed up")
  reaper_fx.step_value(node, -1, false)
  local _, back = reaper.TrackFX_GetFormattedParamValue()
  check_equal(back ~= after, true, "changed down")
end)

test("plugin that ignores the question: a distant choice takes few tries", function()
  fake("ignores_x", 0.0)
  reaper_fx.step_value(node, 1, false)
  check_equal(type_at(param.normalized), "Bright Hall", "next")
  check_equal(param.set_calls < 30, true, "tries: " .. param.set_calls)
end)

test("a very narrow choice is not jumped over", function()
  fake("narrow", 0.1)
  reaper_fx.step_value(node, 1, false)
  check_equal(narrow_at(param.normalized), "Medium", "up")
  fake("narrow", 0.9)
  reaper_fx.step_value(node, -1, false)
  check_equal(narrow_at(param.normalized), "Medium", "down")
end)

reaper = nil
