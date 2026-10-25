-- @description Parameter Organizer
-- @version 0.6
--
-- Browse every track's effect parameters as a tree, by keyboard and speech.
-- Runs in a tiny off-screen window that only captures keys; everything
-- else is spoken through OSARA.
--
-- One tree: tracks, their effects, and inside each effect the user's
-- branches followed by the effect's unplaced parameters (the default
-- branch), which Control+F filters, Control+G sorts and Control+R reverts.
-- Control+X and Control+V move parameters into branches.
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
local selection = require("selection")

local MOD_CTRL, MOD_SHIFT, MOD_ALT = 4, 8, 16

local KEY = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965,
  PAGE_UP = 1885828464, PAGE_DOWN = 1885824110,
  ENTER = 13, SPACE = 32, F2 = 26162, F5 = 26165, F12 = 6697266, ESCAPE = 27,
  DELETE = 6579564,
  CTRL_A = 1, CTRL_C = 3, CTRL_F = 6, CTRL_G = 7, CTRL_N = 14, CTRL_R = 18, CTRL_T = 20, CTRL_V = 22, CTRL_X = 24,
}

-- Settings persist in REAPER's ExtState, so they survive script updates.
local EXTSTATE_SECTION = "ParameterOrganizer"
local settings = settings_lib.new({
  get = function(key)
    if not reaper.HasExtState(EXTSTATE_SECTION, key) then return nil end
    return reaper.GetExtState(EXTSTATE_SECTION, key)
  end,
  set = function(key, text) reaper.SetExtState(EXTSTATE_SECTION, key, text, true) end,
})

-- The source tree is read from the project and never shown: the organized
-- tree, which mirrors it, is the one tree the user moves through.
-- cursor is whichever list has the keyboard: the tree, or the settings
-- list while it is open (tree_cursor then remembers the place).
local source_root, organized_root
local cursor, tree_cursor
-- The selected items, all at one level of the tree.
local sel = selection.new()

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

-- The value spoken after a leaf's label: a parameter's or a setting's.
local function value_of(node)
  if node.kind == "setting" then return settings.value_text(node.data.key) end
  return reaper_fx.formatted_value(node)
end

local function describe_focused(with_state)
  return announce.describe(tree.focused(cursor), with_state, value_of)
end

-- After a move that keeps the selection (Control with the arrows), the
-- focused item says whether it is selected.
local function describe_with_selection(with_state)
  local text = describe_focused(with_state)
  if selection.is_selected(sel, tree.focused(cursor)) then text = text .. ", selected" end
  return text
end

-- After Shift extends the selection (always including the focused item):
-- the focused item and how many are selected.
local function speak_selection_change()
  speak(describe_focused(true) .. ", " .. selection.count(sel) .. " selected")
end

local function speak_focused(with_state)
  speak(describe_focused(with_state))
end

local function in_settings()
  return tree_cursor ~= nil
end

-- The effect whose own level the cursor is on (where its branches and
-- default branch are), or nil.
local function effect_level()
  if in_settings() or cursor.container.kind ~= "fx" then return nil end
  return cursor.container
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
  organized_root = organizer.sync(nil, source_root)
  load_layouts()
  cursor = tree.new_cursor(organized_root)
end

-- An effect's default branch is rebuilt whenever a parameter leaves or
-- joins it, which replaces its nodes. If the focus was on one of them, it
-- follows that parameter when the view still shows it.
local function refresh_default_branch(fx_node)
  -- Selected parameters there are replaced by new nodes, and the list
  -- has changed under the user, so the selection goes.
  if sel.container == fx_node then selection.clear(sel) end
  local focused = tree.focused(cursor)
  local count = organizer.refresh_unplaced(fx_node)
  if cursor.container ~= fx_node then return count end
  if focused and focused.data.unplaced then
    for i, child in ipairs(fx_node.children) do
      if child.data.unplaced and child.data.index == focused.data.index then
        cursor.index = i
        return count
      end
    end
  end
  local last = #fx_node.children
  if cursor.index > last or (cursor.index == 0 and last > 0) then
    cursor.index = math.min(math.max(cursor.index, 1), last)
  end
  return count
end

-- F5: rebuild from the project. The tree keeps its nodes (and the user's
-- branches) for tracks and effects that still exist, so the cursor stays
-- put unless its item was removed.
local function refresh()
  source_root = reaper_fx.build_source_tree()
  organizer.sync(organized_root, source_root)
  load_layouts()
  local c = cursor
  if not tree.contains(organized_root, c.container) or c.index > #c.container.children then
    cursor = tree.new_cursor(organized_root)
  end
  speak("Refreshed. " .. describe_focused(true))
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

-- Control+N: a new branch at the current level. A path such as "freq/min"
-- also creates the branches nested inside it, reusing any that exist.
-- The focus goes to the top branch.
local function create_branch()
  if in_settings() or not organizer.can_create_branch(cursor) then
    speak("Not available here")
    return
  end
  local path = prompt_text("New branch", "Branch name, or a path such as freq/min:")
  local top, created
  if path then top, created = organizer.create_path(cursor, path) end
  if not top then
    speak("Cancelled")
    return
  end
  if created == 0 then
    speak("Already exists. " .. describe_focused(true))
    return
  end
  save_layout()
  speak(describe_focused(true))
end

-- F2: rename the focused branch or parameter. An empty name gives a
-- parameter back its autolabel; a branch keeps its name.
local function rename()
  local node = tree.focused(cursor)
  if in_settings() or not organizer.can_rename(node) then
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

-- Control+X (and Control+C): remember the selected parameters, or else the
-- focused one, for Control+V. A parameter appears only once in the tree,
-- so pasting moves it; until then it stays where it is.
-- clipboard is a list of parameter data, in the order heard when cut.
local clipboard

local function cut()
  local nodes = selection.nodes(sel)
  if #nodes == 0 then
    local node = tree.focused(cursor)
    if not node then
      speak("Not available here")
      return
    end
    nodes = { node }
  end
  for _, node in ipairs(nodes) do
    if node.kind ~= "param" then
      speak(#nodes == 1 and "Not available here" or "Only parameters can be cut")
      return
    elseif node.data.missing then
      speak("Missing parameters can't be cut")
      return
    end
  end
  clipboard = {}
  for i, node in ipairs(nodes) do
    local d = node.data
    clipboard[i] = { fx_guid = d.fx_guid, index = d.index, original_name = d.original_name }
  end
  speak(#nodes == 1 and "Cut " .. nodes[1].label or #nodes .. " cut")
end

-- Control+V. In a branch, places the parameter there. At the effect's own
-- level, returns it to unplaced (the default branch). When a paste
-- empties a filtered default branch, the filter has done its job: clear it.
local function paste()
  if in_settings() then
    speak("Not available here")
    return
  end
  if not clipboard then
    speak("Nothing to paste")
    return
  end
  selection.clear(sel)
  local unplacing = effect_level() ~= nil
  local container = cursor.container
  -- Each item goes after the one before, so the group keeps its order.
  local pasted, result, failure = 0, nil, nil
  for _, data in ipairs(clipboard) do
    local _, r = organizer.paste(cursor, data)
    if type(r) == "string" then
      failure = failure or r
    else
      pasted, result = pasted + 1, r
    end
  end
  if pasted == 0 then
    speak(failure)
    return
  end
  save_layout()

  -- When unplacing, the focus may not be on the parameter if the default
  -- branch's view hides it.
  local msg
  if #clipboard > 1 then
    msg = unplacing and pasted .. " unplaced" or pasted .. " pasted into " .. container.label
  elseif unplacing then
    msg = "Unplaced. " .. describe_focused(true)
  else
    msg = describe_focused(true)
    if result then
      msg = msg .. (#result > 0 and ", moved from " .. table.concat(result, ", ") or ", moved")
    end
  end

  local fx_node = tree.enclosing(cursor.container, "fx")
  local remaining = 0
  for _, child in ipairs(fx_node.children) do
    if child.data.unplaced then remaining = remaining + 1 end
  end
  if fx_node.view.filter and remaining == 0 then
    fx_node.view.filter = nil
    refresh_default_branch(fx_node)
    msg = msg .. ". Filter cleared"
  end
  speak(msg)
end

-- Delete: a parameter goes back to unplaced straight away. A branch that
-- holds anything asks first: press Delete again to confirm. Either way the
-- parameters rejoin the effect's default branch.
local pending_delete

local function delete()
  local node = tree.focused(cursor)
  if in_settings() or not organizer.can_delete(node) then
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
  local fx_node = tree.enclosing(cursor.container, "fx")
  selection.clear(sel)
  tree.remove_focused(cursor)
  refresh_default_branch(fx_node)
  save_layout()
  speak("Deleted " .. node.label .. ". " .. describe_focused(true))
end

---------------------------------------------------------------------------
-- The default branch's view: Control+F filters, Control+G sorts and
-- Control+R reverts. Each acts on the effect whose own level the cursor
-- is on, and never moves its branches.

local function view_target()
  local fx_node = effect_level()
  if not fx_node then speak("Not available here") end
  return fx_node
end

local function filter()
  local fx_node = view_target()
  if not fx_node then return end
  local text = prompt_text("Filter", "Show parameters containing:", fx_node.view.filter)
  if not text then
    speak("Cancelled")
    return
  end
  local old = fx_node.view.filter
  fx_node.view.filter = text ~= "" and text or nil
  local count = refresh_default_branch(fx_node)
  if fx_node.view.filter and count == 0 then
    fx_node.view.filter = old
    refresh_default_branch(fx_node)
    speak("Nothing matches " .. text)
    return
  end
  if not fx_node.view.filter then
    speak("Filter cleared. " .. describe_focused(true))
    return
  end
  -- Land on the first match, past the branches.
  tree.move_first(cursor)
  if not tree.is_leaf(tree.focused(cursor)) then tree.move_stop(cursor, true) end
  speak(count .. (count == 1 and " match. " or " matches. ") .. describe_focused(true))
end

local function sort()
  local fx_node = view_target()
  if not fx_node then return end
  fx_node.view.sorted = true
  refresh_default_branch(fx_node)
  speak("Sorted. " .. describe_focused(true))
end

local function revert()
  local fx_node = view_target()
  if not fx_node then return end
  fx_node.view.sorted, fx_node.view.filter = false, nil
  refresh_default_branch(fx_node)
  speak("Original order. " .. describe_focused(true))
end

-- F12 opens the settings list; F12 or Escape returns to the same place.
local function open_settings()
  local list = tree.new_node("root", "Settings")
  for _, def in ipairs(settings_lib.DEFINITIONS) do
    tree.add_child(list, tree.new_node("setting", def.label, { key = def.key }))
  end
  selection.clear(sel)
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
  speak(value_of(node))
end

-- Control+Page Up and Control+Page Down: the maximum or minimum.
local function value_to_extreme(to_max)
  local node = value_target()
  if not node then return end
  if node.kind == "setting" then
    settings.step(node.data.key, to_max and 1 or -1)
  else
    reaper_fx.set_extreme(node, to_max)
  end
  speak(value_of(node))
end

-- Control+T: back to the effect's own level, landing on the top branch
-- that holds the focus, as pressing Left repeatedly would.
local function to_effect_level()
  local fx_node = not in_settings() and tree.enclosing(cursor.container, "fx")
  if not fx_node then
    speak("Not available here")
    return
  end
  if cursor.container == fx_node then
    speak("Already at the top. " .. describe_focused(true))
    return
  end
  local node = tree.focused(cursor) or cursor.container
  while node.parent ~= fx_node do node = node.parent end
  selection.clear(sel)
  tree.focus_node(cursor, node)
  speak_focused(false)
end

-- Right: entering an effect whose default branch is filtered says so, so
-- the hidden parameters aren't taken for missing.
local function enter()
  if not tree.enter(cursor) then return end
  local fx_node = effect_level()
  if fx_node and fx_node.view.filter then
    speak("Filtered. " .. describe_focused(false))
  else
    speak_focused(false)
  end
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
  -- Down: Home moves towards the last item. Otherwise both are reversed.
  -- Page Up and Page Down are never swapped.
  local to_end
  if code == KEY.HOME or code == KEY.END then
    to_end = (code == KEY.END) ~= settings.get("swap_home_end")
  end

  -- A branch delete is confirmed only by pressing Delete again straight away.
  if code ~= KEY.DELETE then pending_delete = nil end

  -- Plain movement drops the selection, as in any Windows list.
  local plain_move = plain and (code == KEY.UP or code == KEY.DOWN or code == KEY.LEFT
    or code == KEY.RIGHT or to_end ~= nil or (code > 32 and code < 127))
  if plain_move then selection.clear(sel) end

  local vertical = code == KEY.UP or code == KEY.DOWN
  local selecting = not in_settings()

  if (code == KEY.ESCAPE or code == KEY.F12) and plain and in_settings() then
    close_settings()
  elseif code == KEY.ESCAPE and plain and selection.count(sel) > 0 then
    selection.clear(sel)
    speak("Selection cleared")
  elseif code == KEY.ESCAPE and plain then
    return false
  elseif code == KEY.F12 and plain then
    open_settings()
  elseif (code == KEY.PAGE_UP or code == KEY.PAGE_DOWN) and (plain or shift_only) then
    step_value(code == KEY.PAGE_UP and 1 or -1, shift_only)
  elseif (code == KEY.PAGE_UP or code == KEY.PAGE_DOWN) and ctrl_only then
    value_to_extreme(code == KEY.PAGE_UP)
  elseif selecting and shift_only and (vertical or to_end ~= nil) then
    -- Shift+Up, Shift+Down, Shift+Home, Shift+End: extend the selection.
    local old_index = cursor.index
    local moved
    if vertical then
      moved = (code == KEY.UP and tree.move_prev or tree.move_next)(cursor)
    else
      moved = (to_end and tree.move_last or tree.move_first)(cursor)
    end
    if moved then
      selection.extend(sel, cursor, old_index)
      speak_selection_change()
    end
  elseif selecting and shift_only and code == KEY.SPACE then
    if tree.focused(cursor) then
      local on = selection.toggle(sel, cursor)
      speak(describe_focused(true) .. (on and ", " or ", not selected, ")
        .. selection.count(sel) .. " selected")
    end
  elseif selecting and ctrl_only and code == KEY.CTRL_A then
    local count = selection.select_leaves(sel, cursor)
    speak(count == 0 and "No parameters here" or count .. " selected")
  elseif ctrl_only and vertical then
    -- Control+Up and Control+Down: move, keeping the selection.
    if (code == KEY.UP and tree.move_prev or tree.move_next)(cursor) then
      speak(describe_with_selection(true))
    end
  elseif to_end ~= nil and ctrl_only then
    local move = to_end and tree.move_last or tree.move_first
    if move(cursor) then speak(describe_with_selection(true)) end
  elseif ctrl_only and code == KEY.CTRL_N then
    create_branch()
  elseif ctrl_only and (code == KEY.CTRL_X or code == KEY.CTRL_C) then
    cut()
  elseif ctrl_only and code == KEY.CTRL_V then
    paste()
  elseif ctrl_only and code == KEY.CTRL_F then
    filter()
  elseif ctrl_only and code == KEY.CTRL_G then
    sort()
  elseif ctrl_only and code == KEY.CTRL_R then
    revert()
  elseif ctrl_only and code == KEY.CTRL_T then
    to_effect_level()
  elseif code == KEY.DELETE and plain then
    delete()
  elseif not plain then
    -- Other modified keys do nothing.
  elseif code == KEY.ENTER then
    type_value()
  elseif code == KEY.UP then
    if tree.move_prev(cursor) then speak_focused(true) end
  elseif code == KEY.DOWN then
    if tree.move_next(cursor) then speak_focused(true) end
  elseif to_end ~= nil then
    if tree.move_stop(cursor, to_end) then speak_focused(true) end
  elseif code == KEY.RIGHT then
    enter()
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
  window_title = "Parameter organizer"
else
  window_title = "Parameter organizer, no effects in this project. F5 refreshes, Escape quits"
end
open_window()
reaper.atexit(gfx.quit)
reaper.defer(loop)
