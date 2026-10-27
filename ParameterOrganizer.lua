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
-- Control+X and Control+V move parameters into branches, and effects
-- within and between tracks.
-- Control+Tab opens the effect's named orderings; F12 the settings list.

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
local orderings = require("orderings")

local MOD_CTRL, MOD_SHIFT, MOD_ALT = 4, 8, 16

local KEY = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965,
  PAGE_UP = 1885828464, PAGE_DOWN = 1885824110,
  ENTER = 13, TAB = 9, SPACE = 32, F2 = 26162, F12 = 6697266, ESCAPE = 27,
  DELETE = 6579564,
  CTRL_A = 1, CTRL_B = 2, CTRL_C = 3, CTRL_F = 6, CTRL_G = 7, CTRL_K = 11, CTRL_N = 14, CTRL_R = 18, CTRL_T = 20, CTRL_V = 22, CTRL_X = 24,
}

-- With Control held, gfx.getchar reports Tab and Control+I both as 9.
-- js_ReaScriptAPI, when installed, can tell them apart; without it,
-- Control+I also opens the orderings list, which is harmless.
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

-- The source tree is read from the project and never shown: the organized
-- tree, which mirrors it, is the one tree the user moves through.
-- cursor is whichever list has the keyboard: the tree, or the settings or
-- orderings list while one is open (tree_cursor then remembers the place,
-- and list_kind says which list it is).
local source_root, organized_root
local cursor, tree_cursor, list_kind
-- The effect whose orderings are listed, while that list is open.
local list_fx
-- The selected items, all at one level of the tree.
local sel = selection.new()

-- After a dialog, speech is held until focus is back in the script's
-- window (the loop delivers it), so it isn't lost while focus is elsewhere.
-- Only the latest message is kept. No fixed delay is added: speech rates
-- vary too much for one delay to suit everyone. The one exception is the
-- greeting at startup, which waits STARTUP_DELAY seconds after focus so the
-- screen reader can say the window's title first.
local STARTUP_DELAY = 1
local hold_delay = 0
local awaiting_focus, held_speech, focus_seen_at = false, nil, nil

-- Something to say before the next message, such as a new ordering
-- having been made, so it doesn't compete with that message.
local pending_notice

local function speak(msg)
  if pending_notice then
    msg = pending_notice .. msg
    pending_notice = nil
  end
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
  if now - focus_seen_at < hold_delay then return end
  awaiting_focus, focus_seen_at, hold_delay = false, nil, 0
  if held_speech then reaper.osara_outputMessage(held_speech) end
  held_speech = nil
end

-- The value spoken after a leaf's label: a parameter's or a setting's.
local function value_of(node)
  if node.kind == "setting" then return settings.value_text(node.data.key) end
  if node.kind == "ordering" then return node.data.active and "active" or "" end
  return reaper_fx.formatted_value(node)
end

-- A bypassed effect says so before its name, and a track whose whole
-- chain is bypassed says "bypassed" before its name too.
local function describe_focused(with_state)
  local node = tree.focused(cursor)
  local text = announce.describe(node, with_state, value_of)
  if node and node.kind == "fx" and reaper_fx.is_bypassed(node) then text = "bypassed " .. text end
  if node and node.kind == "track" and reaper_fx.is_chain_bypassed(node) then text = "bypassed " .. text end
  return text
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
  speak(describe_with_selection(with_state))
end

-- True while the settings list or an orderings list is open.
local function in_list()
  return tree_cursor ~= nil
end

-- The effect whose own level the cursor is on (where its branches and
-- default branch are), or nil.
local function effect_level()
  if in_list() or cursor.container.kind ~= "fx" then return nil end
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

-- Each plugin type's named orderings (a container's are its own), loaded
-- once and shared by every instance: storage key -> collection.
local collections = {}

local function collection_key(data)
  if data.is_container then return "container " .. data.guid end
  return data.plugin_key
end

local function collection_for(fx_node)
  local key = collection_key(fx_node.data)
  if not collections[key] then collections[key] = orderings.parse(storage.load(fx_node.data)) end
  return collections[key]
end

-- Calls fn for fx_node and every other instance sharing its orderings.
local function each_instance(fx_node, fn)
  local key = collection_key(fx_node.data)
  tree.walk(organized_root, function(n)
    if n.kind == "fx" and collection_key(n.data) == key then fn(n) end
  end)
end

-- Gives an effect its active ordering's branches and parameters.
local function apply_active(fx_node)
  local coll = collection_for(fx_node)
  layout.apply(fx_node, orderings.text(coll, coll.active), source_names(fx_node.data.guid))
end

-- Gives every organized effect that doesn't have its layout yet its
-- active ordering (new effects appear at startup and after Control+Shift+R).
local function load_layouts()
  tree.walk(organized_root, function(n)
    if n.kind == "fx" and not n.layout_loaded then
      n.layout_loaded = true
      apply_active(n)
    end
  end)
end

local function save_collection(fx_node)
  if storage.save(fx_node.data, orderings.serialize(collection_for(fx_node))) then return true end
  speak("Could not save the layout")
  return false
end

-- Saves the layout of the effect being organized into its active
-- ordering, after every change. Original never changes: the first change
-- made while it is active starts a new ordering. Other instances of the
-- same plugin share the ordering, so they are updated at once (the cursor
-- is never inside them while this one changes).
local function save_layout()
  local fx_node = tree.enclosing(cursor.container, "fx")
  if not fx_node then return end
  local coll = collection_for(fx_node)
  local text = layout.serialize(fx_node)
  if not coll.active then
    if not text:find("\n[BP]\t") then return end
    local name = orderings.new_name(coll)
    orderings.add(coll, name, text)
    orderings.set_active(coll, name)
    pending_notice = "New ordering, " .. name .. ". "
  else
    orderings.set_active_text(coll, text)
  end
  if not save_collection(fx_node) then return end
  each_instance(fx_node, function(n)
    if n ~= fx_node then layout.apply(n, text, source_names(n.data.guid)) end
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
  -- Selected parameters there are replaced by new nodes. In normal mode
  -- the list has changed under the user, so the selection goes; in
  -- multiselect mode it follows them, unless the view now hides them.
  local selected_unplaced = {}
  if sel.sticky then
    for node in pairs(sel.set) do
      if node.data.unplaced and node.parent == fx_node then selected_unplaced[node] = node.data.index end
    end
  elseif sel.scope == fx_node then
    selection.clear(sel)
  end
  local focused = tree.focused(cursor)
  local count = organizer.refresh_unplaced(fx_node)
  if sel.sticky then
    local by_index = {}
    for _, child in ipairs(fx_node.children) do
      if child.data.unplaced then by_index[child.data.index] = child end
    end
    selection.update(sel, function(n)
      local index = selected_unplaced[n]
      return index and by_index[index]
    end)
  end
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

-- Rebuilds from the project. The tree keeps its nodes (and the user's
-- branches) for tracks and effects that still exist.
local function reload()
  source_root = reaper_fx.build_source_tree()
  organizer.sync(organized_root, source_root)
  load_layouts()
end

-- Control+Shift+R: rebuild from the project. The cursor stays put unless its item was
-- removed.
local function refresh()
  reload()
  local c = cursor
  if not tree.contains(organized_root, c.container) or c.index > #c.container.children then
    cursor = tree.new_cursor(organized_root)
  end
  speak("Refreshed. " .. describe_focused(true))
end

-- The screen reader announces the window's title whenever it gains focus:
-- at startup, after a dialog and after the FX browser. At startup the
-- script then names the item it starts on, a second later. (A blank title
-- made the screen reader say "unknown" whenever focus came back.) Nothing
-- is spoken on closing.
local WINDOW_TITLE = "Parameter Organizer"

local function open_window()
  gfx.init(WINDOW_TITLE, 1, 1, 0, -32000, -32000)
end

-- The window, for js_ReaScriptAPI to give focus back to: noted the first
-- time the window has focus, or found by its title.
local window_hwnd

-- Windows does not always return focus to the script's window after a
-- dialog closes (it sometimes goes to REAPER's track view instead), so
-- the loop checks shortly afterwards and takes focus back if needed.
local REFOCUS_DELAY = 0.1
local refocus_check_at

local function window_has_focus()
  return gfx.getchar(65536) & 2 ~= 0
end

local function refocus_window()
  if not window_hwnd and reaper.JS_Window_Find then window_hwnd = reaper.JS_Window_Find(WINDOW_TITLE, true) end
  if window_hwnd and reaper.JS_Window_SetFocus then
    reaper.JS_Window_SetFocus(window_hwnd)
    return
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
  if in_list() or not organizer.can_create_branch(cursor) then
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
  if in_list() or not organizer.can_rename(node) then
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
-- clipboard is a list of parameter data, in the order heard when cut; or,
-- with clipboard.effects set, of effects (see cut_effects).
local clipboard

-- Effects on a track's level: Control+X moves them when pasted, Control+C
-- copies them. Effects inside containers can't be cut yet.
local function cut_effects(nodes, copying)
  for _, node in ipairs(nodes) do
    if node.kind ~= "fx" then
      speak("Cut effects or parameters, not both")
      return
    elseif node.parent.kind ~= "track" then
      speak("Not available inside a container")
      return
    end
  end
  clipboard = { effects = true, copying = copying }
  for i, node in ipairs(nodes) do
    clipboard[i] = { track = node.data.track, guid = node.data.guid }
  end
  local verb = copying and "Copied" or "Cut"
  speak(#nodes == 1 and verb .. " " .. announce.name(nodes[1]) or #nodes .. " " .. verb:lower())
end

local function cut(copying)
  local nodes = selection.nodes(sel)
  if #nodes == 0 then
    local node = tree.focused(cursor)
    if not node then
      speak("Not available here")
      return
    end
    nodes = { node }
  end
  if nodes[1].kind == "fx" then
    cut_effects(nodes, copying)
    return
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

-- Control+V with effects: on a track's level, after the focused effect (or
-- into an empty track), in the order cut. One undo point covers them all.
-- Moved effects stay on the clipboard at their new place, so pasting
-- again moves them again.
local function paste_effects()
  local track_node, focused = cursor.container, tree.focused(cursor)
  if track_node.kind ~= "track" or (focused and focused.kind ~= "fx") then
    speak("Not available here")
    return
  end
  selection.clear(sel)
  local dest = track_node.data.track
  local after, pasted = focused and focused.data.guid, 0
  reaper.Undo_BeginBlock()
  for _, item in ipairs(clipboard) do
    local guid = reaper_fx.place_fx(item.track, item.guid, dest, after, not clipboard.copying)
    if guid then
      if not clipboard.copying then item.track, item.guid = dest, guid end
      after, pasted = guid, pasted + 1
    end
  end
  reaper.Undo_EndBlock(clipboard.copying and "Copy effects" or "Move effects", -1)
  if pasted == 0 then
    speak("Nothing to paste")
    return
  end
  reload()
  tree.focus_node(cursor, organizer.find_fx(organized_root, after))
  speak(pasted == 1 and describe_focused(true) or pasted .. " pasted")
end

-- Control+V. In a branch, places the parameter there. At the effect's own
-- level, returns it to unplaced (the default branch). When a paste
-- empties a filtered default branch, the filter has done its job: clear it.
local function paste()
  if in_list() then
    speak("Not available here")
    return
  end
  if not clipboard then
    speak("Nothing to paste")
    return
  end
  if clipboard.effects then
    paste_effects()
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

-- Delete on a track's level: the selected effects, or the focused one,
-- after asking. One undo point covers them all. Effects inside containers
-- can't be deleted here yet, as they can't be cut.
local function delete_effects()
  local nodes = selection.nodes(sel)
  if #nodes == 0 then nodes = { tree.focused(cursor) } end
  local guids = {}
  for i, node in ipairs(nodes) do
    if node.kind ~= "fx" then
      speak("Delete effects or parameters, not both")
      return
    elseif node.parent.kind ~= "track" then
      speak("Not available inside a container")
      return
    end
    guids[i] = node.data.guid
  end
  local name = #nodes == 1 and announce.name(nodes[1]) or #nodes .. " effects"
  -- The same effects must be asked about and confirmed.
  local key = table.concat(guids, " ")
  if pending_delete ~= key then
    pending_delete = key
    speak("Delete " .. name .. "? Press Delete again to confirm")
    return
  end
  pending_delete = nil
  reaper.Undo_BeginBlock()
  for _, node in ipairs(nodes) do reaper_fx.delete_fx(node.data.track, node.data.guid) end
  reaper.Undo_EndBlock("Delete effects", -1)
  selection.clear(sel)
  reload()
  -- Focus what took the place of the focused effect, or the new last one.
  if tree.contains(organized_root, cursor.container) then
    local count = #cursor.container.children
    cursor.index = math.min(math.max(cursor.index, 1), count)
  else
    cursor = tree.new_cursor(organized_root)
  end
  speak("Deleted " .. name .. ". " .. describe_focused(true))
end

local function delete()
  local node = tree.focused(cursor)
  -- The selection, when there is one, decides whether effects are deleted.
  local first = selection.nodes(sel)[1] or node
  if not in_list() and first and first.kind == "fx" then
    delete_effects()
    return
  end
  if in_list() or not organizer.can_delete(node) then
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
  if not sel.sticky then selection.clear(sel) end
  tree.remove_focused(cursor)
  refresh_default_branch(fx_node)
  -- In multiselect mode, anything selected inside a deleted branch goes.
  selection.update(sel)
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
  tree_cursor, list_kind = cursor, "settings"
  cursor = tree.new_cursor(list)
  speak("Settings. " .. describe_focused(true))
end

-- Closes the settings or orderings list, back to the place in the tree.
local function close_list(prefix)
  cursor = tree_cursor
  tree_cursor, list_kind, list_fx = nil, nil, nil
  speak(prefix .. describe_focused(true))
end

---------------------------------------------------------------------------
-- Named orderings. Control+Tab opens the list for the effect the cursor
-- is in; Control+Tab or Escape closes it. Enter makes the focused
-- ordering active, Control+N adds a copy of the active one, F2 renames
-- and Delete deletes. Original is always first and can't be changed.

-- (Re)builds the orderings list for list_fx, focusing the named ordering.
local function show_orderings(focus_name)
  local coll = collection_for(list_fx)
  local active = coll.active or orderings.ORIGINAL
  local list = tree.new_node("root", "Orderings")
  local index = 1
  for i, name in ipairs(orderings.names(coll)) do
    tree.add_child(list, tree.new_node("ordering", name, { active = name == active }))
    if focus_name and name:lower() == focus_name:lower() then index = i end
  end
  cursor = { container = list, index = index }
end

-- Only from inside an effect, like Control+N: on an effect's name, go in
-- with Right first.
local function open_orderings()
  local fx_node = tree.enclosing(cursor.container, "fx")
  if not fx_node then
    speak("Not available here")
    return
  end
  selection.clear(sel)
  tree_cursor, list_kind, list_fx = cursor, "orderings", fx_node
  show_orderings(collection_for(fx_node).active or orderings.ORIGINAL)
  speak("Orderings for " .. fx_node.label .. ". " .. describe_focused(true))
end

-- Makes an ordering (nil for Original) active for every instance. Their
-- branches are replaced, so a place inside the effect becomes the
-- effect's own level.
local function activate_ordering(name)
  local coll = collection_for(list_fx)
  orderings.set_active(coll, name)
  save_collection(list_fx)
  each_instance(list_fx, apply_active)
  if tree.contains(list_fx, tree_cursor.container) then
    tree_cursor = { container = list_fx, index = #list_fx.children > 0 and 1 or 0 }
  end
end

-- Enter: make the focused ordering active and return to the tree.
local function choose_ordering()
  local name = tree.focused(cursor).label
  if tree.focused(cursor).data.active then
    close_list(name .. " already active. ")
    return
  end
  activate_ordering(name)
  close_list(name .. " active. ")
end

-- Control+N: a new, empty ordering (like Original), made active. The list
-- stays open, focused on it.
local function new_ordering()
  local coll = collection_for(list_fx)
  local name = prompt_text("New ordering", "Name for a new, empty ordering:", orderings.new_name(coll))
  if not name then
    speak("Cancelled")
    return
  end
  local ok, reason = orderings.can_use_name(coll, name)
  if not ok then
    speak(reason)
    return
  end
  orderings.add(coll, name, orderings.EMPTY_LAYOUT)
  activate_ordering(name)
  show_orderings(name)
  speak("Created. " .. describe_focused(true))
end

-- Control+C and Control+V copy an ordering. They have their own
-- clipboard, so parameters cut in the tree stay ready to paste.
local ordering_clipboard

local function copy_ordering()
  local name = tree.focused(cursor).label
  local coll = collection_for(list_fx)
  ordering_clipboard = { name = name, text = orderings.text(coll, name), key = collection_key(list_fx.data) }
  speak("Copied " .. name)
end

-- Pastes a copy after the focused ordering, named "<name> copy", and
-- focuses it. Only into the same plugin's list: another plugin's
-- parameters are different.
local function paste_ordering()
  if not ordering_clipboard then
    speak("Nothing to paste")
    return
  end
  if ordering_clipboard.key ~= collection_key(list_fx.data) then
    speak("This ordering belongs to another plugin")
    return
  end
  local coll = collection_for(list_fx)
  local name = orderings.copy_name(coll, ordering_clipboard.name)
  -- The focused item's position in the list, counting Original as 1, is
  -- the position after it among the saved orderings.
  orderings.add(coll, name, ordering_clipboard.text, cursor.index)
  save_collection(list_fx)
  show_orderings(name)
  speak("Pasted. " .. describe_focused(true))
end

local function rename_ordering()
  local old = tree.focused(cursor).label
  if orderings.is_original(old) then
    speak("Original can't be renamed")
    return
  end
  local coll = collection_for(list_fx)
  local name = prompt_text("Rename ordering", "New name:", old)
  if not name then
    speak("Cancelled")
    return
  end
  if name:lower() ~= old:lower() then
    local ok, reason = orderings.can_use_name(coll, name)
    if not ok then
      speak(reason)
      return
    end
  elseif name == "" then
    speak("Cancelled")
    return
  end
  orderings.rename(coll, old, name)
  save_collection(list_fx)
  show_orderings(name)
  speak(describe_focused(true))
end

-- Delete asks first: press Delete again to confirm. Deleting the active
-- ordering makes Original active.
local pending_ordering_delete

local function delete_ordering()
  local node = tree.focused(cursor)
  if orderings.is_original(node.label) then
    speak("Original can't be deleted")
    return
  end
  if pending_ordering_delete ~= node then
    pending_ordering_delete = node
    speak("Delete ordering " .. node.label .. "? Press Delete again to confirm")
    return
  end
  pending_ordering_delete = nil
  local coll = collection_for(list_fx)
  local old_index = cursor.index
  orderings.remove(coll, node.label)
  save_collection(list_fx)
  if node.data.active then activate_ordering(nil) end
  -- Focus what took its place, or the new last item.
  local names = orderings.names(coll)
  show_orderings(names[math.min(old_index, #names)])
  speak("Deleted " .. node.label .. ". " .. describe_focused(true))
end

-- Keys in the orderings list. Returns true when the key was used; other
-- keys only move through the list.
local function handle_orderings_key(code, plain, ctrl_only)
  if code ~= KEY.DELETE then pending_ordering_delete = nil end
  if (plain and code == KEY.ESCAPE) or (ctrl_only and code == KEY.TAB) then
    close_list("Orderings closed. ")
  elseif plain and code == KEY.ENTER then
    choose_ordering()
  elseif ctrl_only and code == KEY.CTRL_N then
    new_ordering()
  elseif ctrl_only and code == KEY.CTRL_C then
    copy_ordering()
  elseif ctrl_only and code == KEY.CTRL_V then
    paste_ordering()
  elseif ctrl_only and code == KEY.CTRL_X then
    speak("Not available here")
  elseif plain and code == KEY.F2 then
    rename_ordering()
  elseif plain and code == KEY.DELETE then
    delete_ordering()
  else
    return false
  end
  return true
end

-- Value keys act only on a focused parameter or setting, and speak the
-- new value. A missing parameter (from a saved layout) has no value.
local function value_target()
  local node = tree.focused(cursor)
  if not node or not (node.kind == "param" or node.kind == "setting") then return nil end
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
  local fx_node = not in_list() and tree.enclosing(cursor.container, "fx")
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
  if sel.sticky then selection.forget_anchor(sel) else selection.clear(sel) end
  tree.focus_node(cursor, node)
  speak_focused(false)
end

-- Control+B: bypass the focused effect, or else the one the cursor is
-- in, or bring it back. Only bypassing is spoken, with the effect's name,
-- since inside a container it may not be the effect expected.
local function toggle_bypass()
  local node = tree.focused(cursor)
  if not (node and node.kind == "fx") then node = not in_list() and tree.enclosing(cursor.container, "fx") end
  if in_list() or not node then
    speak("Not available here")
    return
  end
  if reaper_fx.toggle_bypass(node) then speak("bypassed " .. announce.name(node)) end
end

-- Control+Shift+B: bypass the whole effect chain of the focused track, or
-- else the one the cursor is in, or bring it back, as OSARA's B does.
-- Spoken like Control+B: only bypassing, with the track's name.
local function toggle_track_bypass()
  local node = tree.focused(cursor)
  if not (node and node.kind == "track") then node = not in_list() and tree.enclosing(cursor.container, "track") end
  if in_list() or not node then
    speak("Not available here")
    return
  end
  if reaper_fx.toggle_chain_bypass(node) then speak("bypassed " .. node.label) end
end

-- The track the next start lands on, after Control+Shift+F, kept in
-- ExtState only until REAPER closes.
local RETURN_TRACK_KEY = "return_track"
local FX_BROWSER_ACTION = 40271  -- View: Show FX browser window

-- While the FX browser is open: the track it adds to and the guids of the
-- effects that track had, so new ones can be found when it closes.
local browser_watch

-- Control+Shift+F: REAPER's FX browser, adding to the focused track or the
-- one the cursor is in, which becomes the only selected track. When the
-- browser closes, the script takes focus back (see return_from_browser);
-- if it is restarted instead, it starts on that track.
-- Nothing is spoken: the browser announces itself.
local function open_fx_browser()
  local node = tree.focused(cursor)
  if not (node and node.kind == "track") then node = not in_list() and tree.enclosing(cursor.container, "track") end
  if in_list() or not node then
    speak("Not available here")
    return
  end
  reaper.SetOnlyTrackSelected(node.data.track)
  reaper.SetExtState(EXTSTATE_SECTION, RETURN_TRACK_KEY, node.data.guid, false)
  -- The action toggles the browser: when it is already open, close it
  -- first so that opening it again gives it focus.
  if reaper.GetToggleCommandState(FX_BROWSER_ACTION) == 1 then reaper.Main_OnCommand(FX_BROWSER_ACTION, 0) end
  reaper.Main_OnCommand(FX_BROWSER_ACTION, 0)
  browser_watch = { guid = node.data.guid, before = {} }
  for _, child in ipairs(node.children) do
    if child.kind == "fx" then browser_watch.before[child.data.guid] = true end
  end
end

-- The FX browser has closed: refresh, take focus back, and land on the
-- first effect it added, or else on the track.
local function return_from_browser()
  local watch = browser_watch
  browser_watch = nil
  reaper.DeleteExtState(EXTSTATE_SECTION, RETURN_TRACK_KEY, false)
  reload()
  local track_node
  for _, node in ipairs(organized_root.children) do
    if node.kind == "track" and node.data.guid == watch.guid then track_node = node end
  end
  if track_node then
    local target = track_node
    for _, child in ipairs(track_node.children) do
      if child.kind == "fx" and not watch.before[child.data.guid] then
        target = child
        break
      end
    end
    selection.clear(sel)
    tree.focus_node(cursor, target)
  elseif not tree.contains(organized_root, cursor.container) or cursor.index > #cursor.container.children then
    cursor = tree.new_cursor(organized_root)
  end
  -- Speech waits until the window has focus again.
  awaiting_focus = true
  speak(describe_focused(true))
  refocus_window()
  refocus_check_at = reaper.time_precise() + REFOCUS_DELAY
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
  local ctrl_shift = cap & (MOD_CTRL | MOD_SHIFT | MOD_ALT) == MOD_CTRL | MOD_SHIFT

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

  -- Plain movement drops the selection, as in any Windows list, except in
  -- multiselect mode, where the next range starts from the new place.
  local plain_move = plain and (code == KEY.UP or code == KEY.DOWN or code == KEY.LEFT
    or code == KEY.RIGHT or to_end ~= nil or (code > 32 and code < 127))
  if plain_move then
    if sel.sticky then selection.forget_anchor(sel) else selection.clear(sel) end
  end

  local vertical = code == KEY.UP or code == KEY.DOWN
  local selecting = not in_list()

  -- In the orderings list, only its own keys and movement work.
  if list_kind == "orderings" then
    if code == KEY.TAB and ctrl_only and not tab_is_down() then return true end
    if handle_orderings_key(code, plain, ctrl_only) then return true end
    if not (plain_move or (ctrl_only and to_end ~= nil)) then return true end
  end

  if (code == KEY.ESCAPE or code == KEY.F12) and plain and list_kind == "settings" then
    close_list("Settings closed. ")
  elseif ctrl_only and code == KEY.TAB and not in_list() then
    if tab_is_down() then open_orderings() end
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
    -- Shift+Space: the word "unselected" is never spoken, only the count.
    if tree.focused(cursor) then
      selection.toggle(sel, cursor)
      speak(selection.count(sel) .. " selected")
    end
  elseif selecting and ctrl_only and code == KEY.CTRL_A then
    local count = selection.select_leaves(sel, cursor)
    speak(count == 0 and "No parameters here" or selection.count(sel) .. " selected")
  elseif selecting and ctrl_only and code == KEY.CTRL_K then
    -- Control+K: multiselect mode on or off. Turning it on keeps what is
    -- already selected, now held for the whole effect; off clears it.
    sel.sticky = not sel.sticky
    if sel.sticky then
      if sel.scope then sel.scope = tree.enclosing(sel.scope, "fx") or sel.scope end
      speak("Multiselect on")
    else
      local had = selection.count(sel) > 0
      selection.clear(sel)
      speak(had and "Multiselect off, selection cleared" or "Multiselect off")
    end
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
    cut(code == KEY.CTRL_C)
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
  elseif ctrl_only and code == KEY.CTRL_B then
    toggle_bypass()
  elseif ctrl_shift and code == KEY.CTRL_B then
    toggle_track_bypass()
  elseif ctrl_shift and code == KEY.CTRL_F then
    open_fx_browser()
  elseif ctrl_shift and code == KEY.CTRL_R and not in_list() then
    refresh()
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
    awaiting_focus, held_speech, focus_seen_at, hold_delay = false, nil, nil, 0
    -- REAPER returns floats; tree and key lookups want integers.
    code = math.tointeger(code) or code
    local cap = math.tointeger(gfx.mouse_cap) or 0
    if not handle_key(code, cap) then
      gfx.quit()
      return
    end
  end

  if browser_watch and reaper.GetToggleCommandState(FX_BROWSER_ACTION) ~= 1 then
    return_from_browser()
  end

  if refocus_check_at and reaper.time_precise() >= refocus_check_at then
    refocus_check_at = nil
    if not window_has_focus() then refocus_window() end
  end
  local has_focus = window_has_focus()
  if has_focus and not window_hwnd and reaper.JS_Window_GetFocus then
    window_hwnd = reaper.JS_Window_GetFocus()
  end
  deliver_held_speech(has_focus)

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

-- Starts on the track Control+Shift+F opened the FX browser for, if any,
-- or else on REAPER's current track (the last touched one, which is not
-- the same as the selection).
local function focus_current_track()
  local guid = reaper.GetExtState(EXTSTATE_SECTION, RETURN_TRACK_KEY)
  reaper.DeleteExtState(EXTSTATE_SECTION, RETURN_TRACK_KEY, false)
  if guid == "" then
    local track = reaper.GetLastTouchedTrack and reaper.GetLastTouchedTrack()
    if not track then return end
    guid = reaper.GetTrackGUID(track)
  end
  for _, node in ipairs(organized_root.children) do
    if node.kind == "track" and node.data.guid == guid then
      tree.focus_node(cursor, node)
      return
    end
  end
end

load_trees()
focus_current_track()
-- The greeting: the item the script starts on, once the screen reader has
-- had time to say the window's title. A key press before then drops it.
awaiting_focus, hold_delay = true, STARTUP_DELAY
speak(describe_focused(false))
open_window()
reaper.atexit(gfx.quit)
reaper.defer(loop)
