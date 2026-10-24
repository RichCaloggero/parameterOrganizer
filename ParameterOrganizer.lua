-- @description Parameter Organizer
-- @version 0.1
--
-- Browse every track's effect parameters as a tree, by keyboard and speech.
-- Runs in a tiny off-screen window that only captures keys; everything
-- else is spoken through OSARA.
--
-- This version (build step 3) browses the source tree read-only.

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
package.path = script_dir .. "lib/?.lua;" .. package.path

local tree = require("tree")
local announce = require("announce")
local reaper_fx = require("reaper_fx")

local MOD_CTRL, MOD_SHIFT, MOD_ALT = 4, 8, 16

local KEY = {
  UP = 30064, DOWN = 1685026670, LEFT = 1818584692, RIGHT = 1919379572,
  HOME = 6647396, END = 1752132965,
  F5 = 26165, ESCAPE = 27,
}

-- The screen reader announces the window when it gains focus, which can cut
-- off speech sent at the same moment, so the greeting waits a little.
local GREETING_DELAY = 0.5

local root, cursor

local function speak(msg)
  reaper.osara_outputMessage(msg)
end

local function speak_focused(with_state)
  speak(announce.describe(tree.focused(cursor), with_state, reaper_fx.formatted_value))
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

  speak("Refreshed. " .. announce.describe(tree.focused(cursor), true, reaper_fx.formatted_value))
end

-- Returns false when the script should stop.
local function handle_key(code, cap)
  local plain = cap & (MOD_CTRL | MOD_SHIFT | MOD_ALT) == 0

  if code == KEY.ESCAPE and plain then
    speak("Parameter organizer closed")
    return false
  elseif not plain then
    -- Modified keys arrive in later build steps.
  elseif code == KEY.UP then
    if tree.move_prev(cursor) then speak_focused(true) end
  elseif code == KEY.DOWN then
    if tree.move_next(cursor) then speak_focused(true) end
  elseif code == KEY.HOME then
    if tree.move_first(cursor) then speak_focused(true) end
  elseif code == KEY.END then
    if tree.move_last(cursor) then speak_focused(true) end
  elseif code == KEY.RIGHT then
    if tree.enter(cursor) then speak_focused(false) end
  elseif code == KEY.LEFT then
    if tree.leave(cursor) then speak_focused(false) end
  elseif code == KEY.F5 then
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
    local first = tree.focused(cursor)
    if first then
      speak("Parameter organizer. " .. announce.describe(first, true, reaper_fx.formatted_value))
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
