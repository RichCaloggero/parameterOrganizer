# Parameter Organizer: Implementation Plan

This plan implements goal.md as a REAPER Lua script, with decisions from the planning interview of 2026-10-24.

## Architecture

This follows the pattern proven in Lo-lo's Speak FX Params suite (in this folder).

- A 1 by 1 pixel gfx window placed off screen holds keyboard focus: `gfx.init(title, 1, 1, 0, -32000, -32000)`. The title names the current tree, so the screen reader announces something useful when focus lands on it.
- A `reaper.defer` loop polls `gfx.getchar()` and dispatches keys. Modifiers come from `gfx.mouse_cap` (4 Control, 8 Shift, 16 Alt). A return value below zero means the window closed: save and stop. Escape also ends the script.
- `reaper.atexit` saves the layout, so nothing is lost if REAPER stops the script.
- All speech goes through `reaper.osara_outputMessage`, falling back to the ReaScript console if OSARA is missing.
- Relaunch: call `reaper.set_action_options(1)` at startup (REAPER 7.03 or later), so pressing the shortcut again closes the running copy instead of REAPER asking about it. Lo-lo instead uses a launcher that runs action 41898, which closes every running script; that is not copied here because it would kill unrelated scripts.
- Text entry (new branch, rename, exact value): see "Text entry" below.

### Key codes

Taken from Lo-lo's script. The key spike (2026-10-24) confirmed the arrows, Shift+Up and Shift+Down, Home, End, Page Up, Page Down, Enter, Tab, Shift+Tab, F2, F5, F6, Escape, Delete, Control+C, Control+X, Control+V and Control+N.

Findings from the spike:

- Shift+Tab arrives as 9, the same as Tab; the Shift flag in `gfx.mouse_cap` tells them apart.
- Control+Tab arrives as 9 with the Control flag, which is identical to Control+I. Decision: js_ReaScriptAPI stays optional. When it is present, its key state separates Control+Tab from Control+I. Without it, Control with code 9 switches trees, and Control+I does the same, which is harmless because Control+I is unused.
- Focus returned to the window after the `GetUserInputs` prompt: keys kept arriving, and no focus loss was logged.
- The startup announcement can be cut off by the screen reader announcing the new window, so speech at startup is delayed by about half a second.

- Up 30064, Down 1685026670, Left 1818584692, Right 1919379572.
- Home 6647396, End 1752132965, Page Up 1885828464, Page Down 1885824110.
- Enter 13, Tab 9 (Control+Tab is 9 with the Control flag), Delete 6579564, Escape 27.
- F2 26162, F5 26165.
- Control+letter arrives as 1 to 26: Control+C 3, Control+N 14, Control+V 22, Control+X 24.
- Some combinations arrive as 0 from `gfx.getchar`. Lo-lo works around this by reading key state with js_ReaScriptAPI's `JS_VKeys_GetState`. Use that only for any key the spike shows is missing.

### Text entry

Decision: use `reaper.GetUserInputs`, REAPER's own dialog. It needs little code and screen readers already handle it.

- All prompts go through one function, `prompt_text(title, default)`, so switching approach later only changes that function.
- If the key spike shows focus doesn't return to the gfx window afterwards, first try refocusing it with js_ReaScriptAPI.
- Only if that fails, replace `prompt_text` with an in-script line editor like Lo-lo's: typed characters, Left and Right, Backspace, Delete, Home and End handled inside the gfx window and echoed by speech.

## Scope

- Track effects on all tracks, plus the master track.
- Take (item) effects are excluded from the first version.
- REAPER 7 containers are shown nested (Rich's choice): a container appears like an effect; inside it come the effects it holds (containers nested to any depth), then the container's own parameters. The organized tree mirrors this; the user's branches inside a container always follow its effects. Effects inside containers are addressed with the IDs from the `container_item.N` named config parameter.

## Data model

- A node has: kind (track, fx, branch, param), label, parent, children, and for params a parameter reference.
- A parameter reference holds the parameter index, the original parameter name, and an optional user label.
- Source tree: built from the project at startup and on refresh. Tracks and effects are matched by GUID.
- Organized tree: the track and effect levels mirror the project automatically. Under each effect, the branches come from that plugin type's saved layout.
- Each tree remembers its own focused node.

## Saving

- One layout per plugin type, shared by every instance in every project.
- Plugins are keyed by REAPER's plugin identifier (`fx_ident` named config parameter), not by the instance name.
- Files live in a `ParameterOrganizer` folder inside the REAPER resource path, one file per plugin type.
- Parameters are stored by index plus original name. On load, if the name at that index doesn't match, the script searches by name. If it still can't find the parameter, it marks it "missing" and announces that.
- Saving happens after every change.
- Consequence: the same plugin on two tracks shows the same branches. Editing the layout under one changes both. Values stay per instance.

## Keyboard

### Navigation, both trees

- Up and Down: previous and next item at the same level. Speech gives the label, then the value for a parameter, or "collapsed" for anything else. Position ("3 of 8") is never spoken.
- State is spoken only when moving with Up and Down (and the other same-level moves: Home, End, type-ahead). Right and Left speak the item landed on without its state.
- Expanded and collapsed (option A): Right expands a branch and focuses its first child in one step; Left closes the current branch and focuses its parent in one step. So every item reached with Up and Down is collapsed, and "collapsed" signals that it can be entered with Right.
- Right: enter a branch and focus its first child. An empty branch can still be entered: focus sits on an empty position inside it, speech says "empty", and Control+N or Control+V there creates its first item.
- Left: go to the parent.
- Home and End: last and first item at the current level, by default. The "Home and End" setting (F12; default swapped, because Home sits below End on Rich's keyboard) reverses Home and End everywhere they are used.
- A letter key: jump to the next item at this level starting with that letter.
- Control+Tab: switch trees and announce which one is now active.
- F5: rebuild from the project.
- Escape: quit.

### Values, on any parameter in either tree

- Shift+Up and Shift+Down: small step, 1% of the range.
- Page Up and Page Down: large step, 10% of the range.
- Shift+Home and Shift+End: with the "Home and End" setting swapped (the default), Shift+Home sets the minimum and Shift+End the maximum. The rule, like Down and Up: the lower key goes down (last item, minimum) and the upper key goes up (first item, maximum). With the setting off, both are reversed.
- Steps always change the display: if a plain step would display the same (a choice slider such as a reverb type, or a very large range), the search continues to the next setting that displays differently. Plugins that answer "what would you display at x?" with their current display (ValhallaVintageVerb) are detected and searched by setting and reading the real display, restoring the value if nothing changes.
- REAPER's built-in Bypass and Delta report no step sizes, so they are recognised by name among the last three parameters and treated as switches.
- Parameters with set positions (switches, mode menus) use the step sizes the plugin reports.
- Enter: type an exact value in the plugin's own units. The script searches for the matching setting, and falls back to 0 to 100 percent if the plugin doesn't respond well to that.
- After every change, speak the value as the plugin displays it.

### Organizing

- Control+C: in the source tree, copy the focused parameter.
- Control+X: in the organized tree, cut the focused parameter.
- Control+V: in the organized tree, paste at the current level, right after the focused item, using the same rule as Control+N. It never pastes inside the focused item; to paste into a branch, enter it first with Right. Pasting is only allowed under the matching effect, so on an effect name it says "not available here".
- Control+N: create a branch at the current level, right after the focused item, then prompt for its name. It never creates inside the focused item; to create inside a branch, enter it first with Right.
- F2: rename the focused branch or parameter. Clearing a parameter's name restores the autolabel.
- Delete on a parameter: return it to unplaced.
- Delete on a branch: ask for confirmation, then return everything inside it to unplaced.
- Track and effect levels can't be renamed, deleted, or have branches created beside them. Trying (including Control+N on an effect name) says "not available here".

## Settings

- F12 opens the settings list; F12 or Escape closes it and returns to the same place in the tree.
- The list uses the tree's keys: Up, Down, Home, End and type-ahead move; Shift+Up, Shift+Down, Page Up, Page Down, Shift+Home and Shift+End change the focused setting. Each setting speaks its label and value.
- Settings are defined in `lib/settings.lua` and stored in REAPER's persistent ExtState (section "ParameterOrganizer"), so they survive script updates.
- Current settings: "Home and End" (default swapped).
- Future idea (Rich): settable keyboard shortcuts in the settings list.

## Placement rules

- Each source parameter appears at most once in the organized tree.
- Pasting a parameter that is already placed moves it, and speaks something like "moved from frequency, min".
- In the source tree, parameters announce where they are placed, or "unplaced".

## Autolabeling

1. Collect the words of every user-created branch above the pasted parameter. Track and effect names are not included.
2. Split the parameter's original name into words on spaces, underscores, hyphens and lower-to-upper case changes.
3. Remove words that match an ancestor word, ignoring case.
4. If nothing is left, keep the original name.
5. Recompute the label whenever the parameter moves or an ancestor is renamed, unless the user set a label with F2.

Known limit: abbreviations such as "Atk" or "L" are not matched. A synonym table can be added later if this turns out to matter.

## Files

- `ParameterOrganizer.lua`: entry point, window, key loop, speech.
- `lib/tree.lua`: nodes and navigation. Plain Lua with no REAPER calls, so it can be tested outside REAPER.
- `lib/autolabel.lua`: plain Lua, testable outside REAPER.
- `lib/reaper_fx.lua`: reads tracks, effects and parameters, and changes values.
- `lib/storage.lua`: saves and loads layouts.

## Build order

1. Key spike: a throwaway script that speaks the `gfx.getchar` code and modifier state for each key press. Confirm the codes listed under "Key codes", especially Control+N and Control+Tab, and check that REAPER and the screen reader don't intercept any of them. Also press F2 to open a `GetUserInputs` prompt, and check that keys reach the script again after the prompt closes.
2. `tree.lua` and `autolabel.lua` with standalone tests.
3. Source tree: build it from the project and navigate it read-only, with speech.
4. Value adjustment on parameters.
5. Organized tree: the mirrored levels, Control+N, F2 and Control+Tab.
6. Copy, cut, paste, delete and autolabel.
7. Saving and loading.
8. Polish: type-ahead, Home and End, refresh, and announcing missing parameters.
