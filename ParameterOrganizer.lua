-- @description Parameter Organizer
-- @version 0.6
--
-- Browse every track's effect parameters as a tree, by keyboard and speech.
-- Runs in a tiny off-screen window that only captures keys; everything
-- else is spoken through OSARA.
--
-- This version (build step 7) browses the source tree, changes values, and
-- builds the organized tree (Control+Tab switches trees): branches, and
-- parameters copied in with Control+C and Control+V.
-- F12 opens the settings list.

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
package.path = script_dir .. "lib/?.lua;" .. package.path

local tree = require("tree")
local announce = require("announce")
local reaper_fx = require("reaper_fx")
local settings_lib = require("settings")
local organizer = require("organizer")
local layout = require("layout")
local storage = require("storage")

local MOD_CTRL, MOD_SHIFT, MOD_ALT = 4, 8, 16

local KEY = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965,
  PAGE_UP = 1885828464, PAGE_DOWN = 1885824110,
  ENTER = 13, TAB = 9, F2 = 26162, F5 = 26165, F12 = 6697266, ESCAPE = 27,
  DELETE = 6579564,
  CTRL_C = 3, CTRL_N = 14, CTRL_V = 22, CTRL_X = 24,
}

-- With Control held, gfx.getchar reports Tab and Control+I both as 9.
-- js_ReaScriptAPI, when installed, can tell them apart; without it,
-- Control+I also switches trees, which is harmless as it is unused.
local VK_TAB = 0x09
local function tab_is_down()
  if not reaper.JS_VKeys_GetState then return true end
  return (reaper.JS_VKeys_GetState(-2):byte(VK_TAB) or 0) ~= 0
end

-- Settings persist in REAPER's ExtState, so they survive script updates.
local EXTSTATE_SECTION = "ParameterOrganizer"
local settings = settings_lib.new({
  get = function(key)
    if not reaper.HasExtState(EXTSTATE_SECTION, key) then return nil end
    return reaper.GetExtState(EXTSTATE_SECTION, key)
  end,
  set = function(key, text) reaper.SetExtState(EXTSTATE_SECTION, key, text, true) end,
})

-- Two trees: the source tree (everything in the project) and the organized
-- tree (the user's branches). Each keeps its own cursor.
-- cursor is whichever list has the keyboard: the active tree, or the
-- settings list while it is open (tree_cursor then remembers the place).
local source_root, organized_root
local source_cursor, organized_cursor
local cursor, tree_cursor

-- After a dialog, speech is held until focus is back in the script's
-- window (the loop delivers it), so it isn't lost while focus is elsewhere.
-- Only the latest message is kept. No fixed delay is added: speech rates
-- vary too much for one delay to suit everyone.
local AFTER_DIALOG_DELAY = 0
local awaiting_focus, held_speech, focus_seen_at = false, nil, nil

local function speak(msg)
  if awaiting_focus then
    held_speech = msg
    return
  end
  reaper.osara_outputMessage(msg)
end

local function deliver_held_speech(has_focus)
  if not awaiting_focus then return end
  if not has_focus then
    focus_seen_at = nil
    return
  end
  local now = reaper.time_precise()
  focus_seen_at = focus_seen_at or now
  if now - focus_seen_at < AFTER_DIALOG_DELAY then return end
  awaiting_focus, focus_seen_at = false, nil
  if held_speech then reaper.osara_outputMessage(held_speech) end
  held_speech = nil
end

-- Where a source parameter is placed in the organized tree, for example
-- "placed in Q, attack", or "unplaced".
local function placement_of(node)
  local fx_node = organizer.find_fx(organized_root, node.data.fx_guid)
  local placed = fx_node and organizer.find_placed(fx_node, node.data.index)
  if not placed then return "unplaced" end
  local path = organizer.branch_path(placed)
  if #path == 0 then return "placed" end
  return "placed in " .. table.concat(path, ", ")
end

local function in_source_tree(node)
  return node.parent and tree.contains(source_root, node)
end

-- The value spoken after a leaf's label: a parameter's or a setting's.
-- Source parameters also say where they are placed.
local function value_of(node)
  if node.kind == "setting" then return settings.value_text(node.data.key) end
  local value = reaper_fx.formatted_value(node)
  if in_source_tree(node) then return value .. ", " .. placement_of(node) end
  return value
end

-- After a value change, only the new value is spoken.
local function new_value_of(node)
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

local function in_organized()
  return cursor == organized_cursor
end

-- The names of one effect instance's parameters, by index, from the
-- source tree: what a saved layout is matched against.
local function source_names(fx_guid)
  local names = {}
  tree.walk(source_root, function(n)
    if n.kind == "param" and n.data.fx_guid == fx_guid then names[n.data.index] = n.data.original_name end
  end)
  return names
end

-- Gives every organized effect that doesn't have its layout yet the one
-- saved for it (new effects appear at startup and after F5).
local function load_layouts()
  tree.walk(organized_root, function(n)
    if n.kind == "fx" and not n.layout_loaded then
      n.layout_loaded = true
      local text = storage.load(n.data)
      if text then layout.apply(n, text, source_names(n.data.guid)) end
    end
  end)
end

-- Saves the layout of the effect being organized, after every change.
-- Other instances of the same plugin share the layout, so they are
-- updated at once (the cursor is never inside them while this one changes).
local function save_layout()
  local fx_node = tree.enclosing(cursor.container, "fx")
  if not fx_node then return end
  local text = layout.serialize(fx_node)
  if not storage.save(fx_node.data, text) then
    speak("Could not save the layout")
    return
  end
  if fx_node.data.is_container then return end
  tree.walk(organized_root, function(n)
    if n.kind == "fx" and n ~= fx_node and not n.data.is_container
       and n.data.plugin_key == fx_node.data.plugin_key then
      layout.apply(n, text, source_names(n.data.guid))
    end
  end)
end

local function load_trees()
  source_root = reaper_fx.build_source_tree()
  source_cursor = tree.new_cursor(source_root)
  organized_root = organizer.sync(nil, source_root)
  load_layouts()
  organized_cursor = tree.new_cursor(organized_root)
  cursor = source_cursor
end

-- After a rebuild, keep the source cursor on the same item if it still
-- exists; the old nodes are gone, so it is found again by identity.
local function refocus_source(old_cursor)
  local target = tree.focused(old_cursor) or old_cursor.container
  local was_focused = target ~= old_cursor.container
  local id = target.kind ~= "root" and reaper_fx.identity(target)

  local found = id and tree.walk(source_root, function(n)
    return n.kind ~= "root" and reaper_fx.identity(n) == id
  end)
  if found and was_focused then
    tree.focus_node(source_cursor, found)
  elseif found then
    source_cursor.container = found
    source_cursor.index = #found.children > 0 and 1 or 0
  end
end

-- F5: rebuild from the project. The organized tree keeps its nodes (and
-- the user's branches) for tracks and effects that still exist, so its
-- cursor stays put unless its item was removed.
local function refresh()
  local was_organized = in_organized()
  local old_source_cursor = source_cursor

  source_root = reaper_fx.build_source_tree()
  source_cursor = tree.new_cursor(source_root)
  refocus_source(old_source_cursor)

  organizer.sync(organized_root, source_root)
  load_layouts()
  local c = organized_cursor
  if not tree.contains(organized_root, c.container) or c.index > #c.container.children then
    organized_cursor = tree.new_cursor(organized_root)
  end

  cursor = was_organized and organized_cursor or source_cursor
  speak("Refreshed. " .. describe_focused(true))
end

-- Control+Tab: switch between the two trees.
local function switch_tree()
  if in_organized() then
    cursor = source_cursor
    speak("Source tree. " .. describe_focused(true))
  else
    cursor = organized_cursor
    speak("Organized tree. " .. describe_focused(true))
  end
end

-- The screen reader announces the window's name when it gains focus, so
-- the name is the greeting: the script speaks nothing of its own at
-- startup (which would collide with that announcement) or on closing.
local window_title

local function open_window()
  gfx.init(window_title, 1, 1, 0, -32000, -32000)
end

-- Windows does not always return focus to the script's window after a
-- dialog closes (it sometimes goes to REAPER's track view instead), so
-- the loop checks shortly afterwards and takes focus back if needed.
local REFOCUS_DELAY = 0.1
local refocus_check_at

local function window_has_focus()
  return gfx.getchar(65536) & 2 ~= 0
end

local function refocus_window()
  if reaper.JS_Window_Find and reaper.JS_Window_SetFocus then
    local hwnd = reaper.JS_Window_Find(window_title, true)
    if hwnd then
      reaper.JS_Window_SetFocus(hwnd)
      return
    end
  end
  -- Without js_ReaScriptAPI: a newly opened window takes focus, as it does
  -- at startup, so close the window and open it again.
  gfx.quit()
  open_window()
end

-- Asks for text in REAPER's dialog. Returns the text with surrounding
-- spaces removed (possibly ""), or nil when cancelled.
local function prompt_text(title, caption, default)
  -- GetUserInputs separates fields with commas, so none may appear inside one.
  local ok, text = reaper.GetUserInputs(title, 1,
    caption:gsub(",", " ") .. ",extrawidth=150", (default or ""):gsub(",", " "))
  refocus_check_at = reaper.time_precise() + REFOCUS_DELAY
  awaiting_focus = true
  if not ok then return nil end
  return text:match("^%s*(.-)%s*$")
end

-- Control+N: a new branch at the current level, after the focused item.
local function create_branch()
  if not in_organized() or not organizer.can_create_branch(cursor) then
    speak("Not available here")
    return
  end
  local name = prompt_text("New branch", "Branch name:")
  if not name or name == "" then
    speak("Cancelled")
    return
  end
  organizer.create_branch(cursor, name)
  save_layout()
  speak(describe_focused(true))
end

-- F2: rename the focused branch or parameter. An empty name gives a
-- parameter back its autolabel; a branch keeps its name.
local function rename()
  local node = tree.focused(cursor)
  if not in_organized() or not organizer.can_rename(node) then
    speak("Not available here")
    return
  end
  local name = prompt_text("Rename", "New name:", node.label)
  if not name or (name == "" and node.kind == "branch") then
    speak("Cancelled")
    return
  end
  if node.kind == "branch" then
    organizer.rename_branch(node, name)
  else
    organizer.rename_param(node, name)
  end
  save_layout()
  speak(describe_focused(true))
end

-- Control+C and Control+X: remember a parameter for Control+V. A parameter
-- appears only once in the organized tree, so pasting either one moves an
-- already placed parameter; cut leaves it in place until then.
local clipboard

local function copy(verb)
  local node = tree.focused(cursor)
  if not node or node.kind ~= "param" then
    speak("Not available here")
    return
  end
  if node.data.missing then
    speak("Missing parameters can't be copied")
    return
  end
  local d = node.data
  clipboard = { fx_guid = d.fx_guid, index = d.index, original_name = d.original_name }
  speak(verb .. " " .. node.label)
end

local function paste()
  if not in_organized() then
    speak("Not available here")
    return
  end
  if not clipboard then
    speak("Nothing to paste")
    return
  end
  local node, result = organizer.paste(cursor, clipboard)
  if not node then
    speak(result)
    return
  end
  save_layout()
  local msg = describe_focused(true)
  if result then
    msg = msg .. (#result > 0 and ", moved from " .. table.concat(result, ", ") or ", moved")
  end
  speak(msg)
end

-- Delete: a parameter goes back to unplaced straight away. A branch that
-- holds anything asks first: press Delete again to confirm.
local pending_delete

local function delete()
  local node = tree.focused(cursor)
  if not in_organized() or not organizer.can_delete(node) then
    speak("Not available here")
    return
  end
  if node.kind == "branch" and #node.children > 0 and pending_delete ~= node then
    pending_delete = node
    local count = organizer.count_params(node)
    speak("Delete " .. node.label .. " and its " .. count ..
      (count == 1 and " parameter" or " parameters") .. "? Press Delete again to confirm")
    return
  end
  pending_delete = nil
  tree.remove_focused(cursor)
  save_layout()
  speak("Deleted " .. node.label .. ". " .. describe_focused(true))
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
-- new value. A missing parameter (from a saved layout) has no value.
local function value_target()
  local node = tree.focused(cursor)
  if not node or not tree.is_leaf(node) then return nil end
  if node.data.missing then
    speak("missing")
    return nil
  end
  return node
end

local function step_value(direction, large)
  local node = value_target()
  if not node then return end
  if node.kind == "setting" then
    settings.step(node.data.key, direction)
  else
    reaper_fx.step_value(node, direction, large)
  end
  speak(new_value_of(node))
end

-- Shift+Home and Shift+End: the minimum or maximum of the range.
local function value_to_extreme(to_max)
  local node = value_target()
  if not node then return end
  if node.kind == "setting" then
    settings.step(node.data.key, to_max and 1 or -1)
  else
    reaper_fx.set_extreme(node, to_max)
  end
  speak(new_value_of(node))
end

local function type_value()
  local node = value_target()
  if not node or node.kind ~= "param" then return end
  local text = prompt_text("Set " .. node.label, node.label .. " value:",
    reaper_fx.formatted_value(node))
  if not text or text == "" then
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
  local ctrl_only = cap & (MOD_CTRL | MOD_SHIFT | MOD_ALT) == MOD_CTRL

  -- Home and End follow the "Home and End" setting. When swapped (for
  -- keyboards where Home sits below End), the lower key goes down, like
  -- Down and Shift+Down: Home moves to the last item and Shift+Home sets
  -- the minimum. Otherwise both are reversed.
  local to_end
  if code == KEY.HOME or code == KEY.END then
    to_end = (code == KEY.END) ~= settings.get("swap_home_end")
  end

  -- A branch delete is confirmed only by pressing Delete again straight away.
  if code ~= KEY.DELETE then pending_delete = nil end

  if (code == KEY.ESCAPE or code == KEY.F12) and plain and in_settings() then
    close_settings()
  elseif code == KEY.ESCAPE and plain then
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
  elseif ctrl_only and code == KEY.TAB and not in_settings() then
    if tab_is_down() then switch_tree() end
  elseif ctrl_only and code == KEY.CTRL_N then
    create_branch()
  elseif ctrl_only and code == KEY.CTRL_C then
    copy("Copied")
  elseif ctrl_only and code == KEY.CTRL_X then
    if in_organized() then copy("Cut") else speak("Not available here") end
  elseif ctrl_only and code == KEY.CTRL_V then
    paste()
  elseif code == KEY.DELETE and plain then
    delete()
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
  elseif code == KEY.F2 then
    rename()
  elseif code > 32 and code < 127 then
    if tree.jump_to_letter(cursor, string.char(code)) then speak_focused(true) end
  end
  return true
end

local function loop()
  local code = gfx.getchar()
  if code < 0 then return end

  if code > 0 then
    -- A key press means the user has moved on: drop held speech.
    awaiting_focus, held_speech, focus_seen_at = false, nil, nil
    -- REAPER returns floats; tree and key lookups want integers.
    code = math.tointeger(code) or code
    local cap = math.tointeger(gfx.mouse_cap) or 0
    if not handle_key(code, cap) then
      gfx.quit()
      return
    end
  end

  if refocus_check_at and reaper.time_precise() >= refocus_check_at then
    refocus_check_at = nil
    if not window_has_focus() then refocus_window() end
  end
  deliver_held_speech(window_has_focus())

  reaper.defer(loop)
end

if not reaper.osara_outputMessage then
  reaper.ShowMessageBox("Parameter Organizer needs the OSARA extension for speech.", "Parameter Organizer", 0)
  return
end

-- Pressing the shortcut while the script runs (say, after switching away)
-- closes it and starts it again, so the shortcut always lands in a
-- focused, working window. (Flag 1: end on relaunch; flag 2: then restart.)
if reaper.set_action_options then
  reaper.set_action_options(1 | 2)
end

load_trees()
if tree.focused(cursor) then
  window_title = "Parameter organizer, source tree"
else
  window_title = "Parameter organizer, no effects in this project. F5 refreshes, Escape quits"
end
open_window()
reaper.atexit(gfx.quit)
reaper.defer(loop)
