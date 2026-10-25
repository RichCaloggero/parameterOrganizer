-- @description Parameter Organizer
-- @version 0.3
--
-- Browse every track's effect parameters as a tree, by keyboard and speech.
-- Runs in a tiny off-screen window that only captures keys; everything
-- else is spoken through OSARA.
--
-- This version (build step 4) browses the source tree and changes values.
-- F12 opens the settings list.

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
package.path = script_dir .. "lib/?.lua;" .. package.path

local tree = require("tree")
local announce = require("announce")
local reaper_fx = require("reaper_fx")
local settings_lib = require("settings")

local MOD_CTRL, MOD_SHIFT, MOD_ALT = 4, 8, 16

local KEY = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965,
  PAGE_UP = 1885828464, PAGE_DOWN = 1885824110,
  ENTER = 13, F5 = 26165, F12 = 6697266, ESCAPE = 27,
}

-- The screen reader announces the window when it gains focus, which can cut
-- off speech sent at the same moment, so the greeting waits a little.
local GREETING_DELAY = 0.5

-- Settings persist in REAPER's ExtState, so they survive script updates.
local EXTSTATE_SECTION = "ParameterOrganizer"
local settings = settings_lib.new({
  get = function(key)
    if not reaper.HasExtState(EXTSTATE_SECTION, key) then return nil end
    return reaper.GetExtState(EXTSTATE_SECTION, key)
  end,
  set = function(key, text) reaper.SetExtState(EXTSTATE_SECTION, key, text, true) end,
})

-- cursor is whichever list has the keyboard: the tree, or the settings list
-- while it is open (tree_cursor then remembers the place in the tree).
local root, cursor, tree_cursor

local function speak(msg)
  reaper.osara_outputMessage(msg)
end

-- The value spoken after a leaf's label: a parameter's or a setting's.
local function value_of(node)
  if node.kind == "setting" then return settings.value_text(node.data.key) end
  return reaper_fx.formatted_value(node)
end

local function describe_focused(with_state)
  return announce.describe(tree.focused(cursor), with_state, value_of)
end

local function speak_focused(with_state)
  speak(describe_focused(with_state))
end

local function in_settings()
  return tree_cursor ~= nil
end

local function load_tree()
  root = reaper_fx.build_source_tree()
  cursor = tree.new_cursor(root)
end

-- F5: rebuild from the project, keeping the focus on the same item if it
-- still exists.
local function refresh()
  local target = tree.focused(cursor) or cursor.container
  local was_focused = target ~= cursor.container
  local id = target.kind ~= "root" and reaper_fx.identity(target)

  load_tree()

  local found = id and tree.walk(root, function(n)
    return n.kind ~= "root" and reaper_fx.identity(n) == id
  end)
  if found and was_focused then
    tree.focus_node(cursor, found)
  elseif found then
    cursor.container = found
    cursor.index = #found.children > 0 and 1 or 0
  end

  speak("Refreshed. " .. describe_focused(true))
end

-- F12 opens the settings list; F12 or Escape returns to the same place.
local function open_settings()
  local list = tree.new_node("root", "Settings")
  for _, def in ipairs(settings_lib.DEFINITIONS) do
    tree.add_child(list, tree.new_node("setting", def.label, { key = def.key }))
  end
  tree_cursor = cursor
  cursor = tree.new_cursor(list)
  speak("Settings. " .. describe_focused(true))
end

local function close_settings()
  cursor = tree_cursor
  tree_cursor = nil
  speak("Settings closed. " .. describe_focused(true))
end

-- Value keys act only on a focused parameter or setting, and speak the
-- new value.
local function step_value(direction, large)
  local node = tree.focused(cursor)
  if not node or not tree.is_leaf(node) then return end
  if node.kind == "setting" then
    settings.step(node.data.key, direction)
  else
    reaper_fx.step_value(node, direction, large)
  end
  speak(value_of(node))
end

-- Shift+Home and Shift+End: the minimum or maximum of the range.
local function value_to_extreme(to_max)
  local node = tree.focused(cursor)
  if not node or not tree.is_leaf(node) then return end
  if node.kind == "setting" then
    settings.step(node.data.key, to_max and 1 or -1)
  else
    reaper_fx.set_extreme(node, to_max)
  end
  speak(value_of(node))
end

local function type_value()
  local node = tree.focused(cursor)
  if not node or node.kind ~= "param" then return end
  -- GetUserInputs separates fields with commas, so none may appear inside one.
  local caption = node.label:gsub(",", " ") .. " value:"
  local current = reaper_fx.formatted_value(node):gsub(",", "")
  local ok, text = reaper.GetUserInputs("Set " .. node.label, 1,
    caption .. ",extrawidth=100", current)
  if not ok then
    speak("Cancelled")
  elseif reaper_fx.set_value_from_text(node, text) then
    speak(reaper_fx.formatted_value(node))
  else
    speak("No setting matches " .. text)
  end
end

-- Returns false when the script should stop.
local function handle_key(code, cap)
  local plain = cap & (MOD_CTRL | MOD_SHIFT | MOD_ALT) == 0
  local shift_only = cap & (MOD_CTRL | MOD_SHIFT | MOD_ALT) == MOD_SHIFT

  -- Home and End follow the "Home and End" setting. When swapped (for
  -- keyboards where Home sits below End), the lower key goes down, like
  -- Down and Shift+Down: Home moves to the last item and Shift+Home sets
  -- the minimum. Otherwise both are reversed.
  local to_end
  if code == KEY.HOME or code == KEY.END then
    to_end = (code == KEY.END) ~= settings.get("swap_home_end")
  end

  if (code == KEY.ESCAPE or code == KEY.F12) and plain and in_settings() then
    close_settings()
  elseif code == KEY.ESCAPE and plain then
    speak("Parameter organizer closed")
    return false
  elseif code == KEY.F12 and plain then
    open_settings()
  elseif shift_only and code == KEY.UP then
    step_value(1, false)
  elseif shift_only and code == KEY.DOWN then
    step_value(-1, false)
  elseif shift_only and to_end ~= nil then
    -- The end of a list is at the bottom, but the top of a range is its
    -- maximum, so the key that goes to the end of a list sets the minimum.
    value_to_extreme(not to_end)
  elseif not plain then
    -- Other modified keys arrive in later build steps.
  elseif code == KEY.PAGE_UP then
    step_value(1, true)
  elseif code == KEY.PAGE_DOWN then
    step_value(-1, true)
  elseif code == KEY.ENTER then
    type_value()
  elseif code == KEY.UP then
    if tree.move_prev(cursor) then speak_focused(true) end
  elseif code == KEY.DOWN then
    if tree.move_next(cursor) then speak_focused(true) end
  elseif to_end ~= nil then
    local move = to_end and tree.move_last or tree.move_first
    if move(cursor) then speak_focused(true) end
  elseif code == KEY.RIGHT then
    if tree.enter(cursor) then speak_focused(false) end
  elseif code == KEY.LEFT then
    if tree.leave(cursor) then speak_focused(false) end
  elseif code == KEY.F5 and not in_settings() then
    refresh()
  elseif code > 32 and code < 127 then
    if tree.jump_to_letter(cursor, string.char(code)) then speak_focused(true) end
  end
  return true
end

local start_time = reaper.time_precise()
local greeted = false

local function loop()
  local code = gfx.getchar()
  if code < 0 then return end

  if not greeted and reaper.time_precise() - start_time >= GREETING_DELAY then
    if tree.focused(cursor) then
      speak("Parameter organizer. " .. describe_focused(true))
    else
      speak("Parameter organizer. No effects in this project. Press F5 after adding some, or Escape to quit.")
    end
    greeted = true
  end

  if code > 0 then
    -- REAPER returns floats; tree and key lookups want integers.
    code = math.tointeger(code) or code
    local cap = math.tointeger(gfx.mouse_cap) or 0
    if not handle_key(code, cap) then
      gfx.quit()
      return
    end
  end

  reaper.defer(loop)
end

if not reaper.osara_outputMessage then
  reaper.ShowMessageBox("Parameter Organizer needs the OSARA extension for speech.", "Parameter Organizer", 0)
  return
end

if reaper.set_action_options then
  reaper.set_action_options(1)
end

load_tree()
gfx.init("Parameter Organizer, source tree", 1, 1, 0, -32000, -32000)
reaper.atexit(gfx.quit)
reaper.defer(loop)
