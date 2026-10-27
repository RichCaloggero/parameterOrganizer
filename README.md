# Parameter Organizer for REAPER

Parameter Organizer is a REAPER script for screen reader users. It lets you browse every effect parameter in your project as a tree, change values from the keyboard, and organize a plugin's parameters into branches of your own design, so that a plugin with dozens of parameters becomes quick to navigate.

Everything is spoken through OSARA. The script runs in a tiny hidden window that only captures the keyboard.

## What it does

- **One tree:** every track (the master track first), each effect on it, and inside each effect its parameters. Effects inside REAPER 7 containers are shown nested inside their container.
- **Use it as it is, or organize:** a small plugin is fine as it comes. For a busy one, you can sort and filter its parameters, or go further and create branches of your own and move parameters into them. For example, a stereo phaser could become freq, then min and max, then left and right.
- **The default branch:** inside an effect, your branches come first. After them come the parameters you haven't placed in a branch yet, in the plugin's own order. This list is called the default branch. You can sort and filter it, and always get back to the original order.
- **Autolabels:** a parameter placed in branches is renamed by removing the words of the branches above it. "left Q attack", placed under the branches Q and attack, becomes simply "left".
- **Named orderings:** each plugin can have several saved organizations. "Original", the plugin with no branches, is always available.
- **Saved per plugin:** your organization of a plugin is saved automatically, and every copy of that plugin, on any track and in any project, gets the same tree.

## Requirements

- REAPER 7 or later.
- The OSARA extension, for speech.
- Optional: the js_ReaScriptAPI extension, available through ReaPack. With it, the script tells Control+Tab apart from Control+I, and returns focus to its window more smoothly after dialogs. Everything works without it.

## Installation

1. Copy `ParameterOrganizer.lua` and the `lib` folder into a folder of your choice inside REAPER's Scripts folder, for example `Scripts\ParameterOrganizer`. Keep the `lib` folder next to the script, because the script loads its parts from there. The `tests` and `spike` folders are only needed for development.
2. In REAPER, open the Actions list, choose New action, then Load ReaScript, and pick `ParameterOrganizer.lua`.
3. With the new action selected, choose Add in the Shortcuts section and give it a key, for example Control+Y.

Run the script from your shortcut, not from the ReaScript editor. Pressing the shortcut while the script is running restarts it. Nothing is lost when it restarts, because everything is saved as you go.

## Getting started

1. Press your shortcut. Your screen reader says "Parameter Organizer", the window's name, and a second later you hear the item you're on. You start on REAPER's current track (the last one you moved to or touched, even when several are selected), or else on the master track.
2. Use Up and Down to reach a track, Right to go into it, Right again to go into an effect, then Up and Down to hear its parameters and their values.
3. Press Control+F and type a word, such as "freq". Only the parameters containing it are left, and you hear how many match.
4. Press Control+A to select them all, then Control+X to cut them.
5. Press Control+N, type a branch name such as "freq", and press Enter. The new branch is placed ahead of the parameters, and you're on it.
6. Press Right to go inside it, and Control+V to paste. The parameters are placed there, with their autolabels. When the last filtered parameter has been moved, the filter clears itself.
7. Press Control+T to go back to the effect's own level, and carry on with the next group.
8. Press Escape to quit. Next time, your branches are still there, for every copy of that plugin.

## Keyboard

### Moving around

- **Up and Down:** the previous or next item at the same level. Branches, tracks and effects say "collapsed", which means you can go into them with Right. Parameters say their value.
- **Right:** go into a track, effect, container or branch, and hear its first item. An empty one says "empty". An effect whose default branch is filtered says "Filtered" first.
- **Left:** close the current level and go back to its parent.
- **Home and End:** move one stop at a time. On a level that has both branches and parameters, such as an effect you have organized, the stops are the first item, the first parameter, and the last item. Elsewhere, they are the first and last item. By default Home and End are swapped: see "Home and End" below.
- **Control+Home and Control+End:** always the first or last item.
- **Control+T:** back to the effect's own level from anywhere inside it, landing on the branch you were in.
- **A letter or digit:** the next item at this level starting with it.
- **Control+B:** bypass the effect you're on or inside, or bring it back. Bypassing says "bypassed" and the effect's name; bringing it back says nothing. Inside a container, on one of its own branches or parameters, that's the container. A bypassed effect says "bypassed" before its name whenever you land on it.
- **Control+Shift+B:** bypass every effect on the track you're on or inside, or bring them back, like B in OSARA (the track's FX button). Bypassing says "bypassed" and the track's name; bringing them back says nothing. Such a track says "bypassed" before its name whenever you land on it.
- **Control+Tab:** the named orderings for the effect you're in. See "Named orderings" below.
- **F5:** mute the track you're on or inside, or unmute it, like F5 in REAPER, which can't be reached while the script has focus. Says "muted" or "unmuted".
- **Control+Shift+R:** refresh from the project, after adding, removing or moving effects.
- **F12:** open the settings list.
- **Escape:** clear the selection, if there is one. Otherwise, quit.

### Changing values

- **Page Up and Page Down:** a small step up or down. Each step always changes what the plugin displays, so a selector such as a reverb type moves one choice at a time.
- **Shift+Page Up and Shift+Page Down:** a large step, about a tenth of the range.
- **Control+Page Up and Control+Page Down:** the maximum or the minimum.
- **Enter:** type an exact value in the plugin's own units, for example "2500", "2.5 kHz" or "-6". For selectors, type the word shown, for example "Plate".
- REAPER's own Bypass and Delta parameters, which every effect has, work as on/off switches: the upward keys turn them on, and the downward keys turn them off.

Page Up and Page Down are never swapped. Value changes are not added to REAPER's undo history.

### Sorting and filtering the default branch

These work on an effect's own level, and only affect the parameters you haven't placed yet. Your branches stay where they are.

- **Control+G:** sort in natural order, ignoring case, so "band 2" comes before "band 10".
- **Control+F:** show only the parameters whose names contain the text you type. Case and extra spaces don't matter, but the words must be next to each other and in the order you type them. You hear how many match, and land on the first. An empty entry clears the filter. When you move the last filtered parameter into a branch, the filter clears itself.
- **Control+R:** back to the original order, with no filter.

Sorting and filtering change nothing that's saved.

### Selecting

There are three ways to select several parameters: Shift with the arrows for a few neighbours, a filter plus Control+A for a named group, and multiselect mode for a scattered handful.

Normally, selection works within one level, as in any Windows list:

- **Shift+Up and Shift+Down:** extend the selection. You hear how many are selected.
- **Shift+Home and Shift+End:** extend the selection to the first or last item.
- **Shift+Space:** select or unselect the focused item. You hear how many are now selected, for example "2 selected".
- **Control+Up and Control+Down:** move without changing the selection. A selected item says "selected".
- **Control+A:** select every parameter at this level, skipping branches.
- Moving with a plain arrow key, Home, End or a letter clears the selection.
- **Escape:** clear the selection.

**Control+K** turns multiselect mode on or off, and says which each time. It never changes by itself. In multiselect mode:

- **Moving never clears the selection,** so you can wander, pick with Shift+Space, and move on. Only selected items say "selected".
- **The selection can span levels within one effect,** for example a parameter from one branch and another from the default branch. Selecting in another effect starts a new selection.
- **Shift with the arrows and Control+A add** to the selection instead of replacing it.
- **Escape** clears the selection, and the mode stays on.
- **Turning the mode off** clears the selection.

Cut and paste work the same in both modes. Parameters selected from several places are pasted in tree order.

### Organizing

- **Control+N:** create a branch. On an effect's own level, it goes after your other branches; inside a branch, it goes after the focused item. To create a branch inside another one, go into it first with Right. You can type a path, such as "freq/min", to create a branch with others nested inside it in one step. Branches that already exist are reused, so "freq/max" next to an existing "freq" only adds "max". You land on the top branch of the path.
- **Control+X:** cut the selected parameters, or the focused one. They stay where they are until you paste. Control+C does the same.
- **Control+V:** paste. Inside a branch, the parameters go after the focused item, in the order you heard them when you cut them. On an effect's own level, pasting returns parameters to the default branch, unplaced. Each parameter appears only once, so pasting moves it, and you hear where it came from. A parameter can only be pasted inside its own effect.
- **F2:** rename the focused branch, or a parameter you have placed in a branch. Clearing a parameter's name gives it back its autolabel.
- **Delete:** return a placed parameter to the default branch. On a branch with anything in it, you're asked first: press Delete again to confirm, and its parameters return to the default branch.

Tracks and effects mirror your project, so they can't be renamed here, and tracks can't be deleted.

### Moving and copying effects

On a track's level, where its effects are, cut and paste work on effects, within one track or between tracks, without the FX browser:

- **Control+X:** cut the selected effects, or the focused one. They stay where they are until you paste.
- **Control+C:** copy them instead. Each paste then adds new copies.
- **Control+V:** paste after the focused effect, in the order you cut them, and land on the last one pasted. To paste onto a track with no effects, go into it with Right (it says "empty") and paste there. Moved effects can be pasted again to move them on. Each paste is one step in REAPER's undo history.

- **Delete:** delete the selected effects, or the focused one. You're asked first: press Delete again to confirm. Each delete is one step in REAPER's undo history.
- **Control+Shift+F:** open REAPER's FX browser to add a new effect to the track you're on or inside. That track becomes the only selected one, so the browser adds to it. When you close the browser, the script takes focus back and lands on the first effect you added, or on the track if you added none. If you press your shortcut for the script instead, it starts on that track.

Effects inside containers can't be cut or deleted yet, and effects can't be pasted into a container.

## Named orderings

Each plugin can have several saved organizations, called orderings. One of them is active, and every copy of the plugin shows it.

- **Original** is always first in the list. It's the plugin with no branches: every parameter in its own order. It can't be changed, renamed or deleted, so you can always get back to it.
- **Your first change** to a plugin while Original is active starts a new ordering, called "Ordering 1", and you hear "New ordering".

Press Control+Tab anywhere inside an effect to open its orderings list. On an effect's name, go into it with Right first; elsewhere Control+Tab says "Not available here". Inside a container, you get the orderings of the effect you're in: the container's own, or those of an effect it holds once you've gone into that effect. The active ordering says "active". In the list:

- **Up, Down, Home and End:** move through the orderings.
- **Enter:** make the focused ordering active, and go back to the tree. If you were inside the effect, you land on its own level.
- **Control+N:** add a new, empty ordering and make it active. Give it a name. The list stays open, so press Control+Tab or Escape to start organizing.
- **Control+C:** copy the focused ordering.
- **Control+V:** paste a copy after the focused ordering, named, for example, "Ordering 1 copy". Press F2 to rename it and Enter to switch to it. An ordering can only be pasted into the same plugin's list. Copying an ordering doesn't affect parameters you've cut in the tree.
- **F2:** rename the focused ordering.
- **Delete:** delete the focused ordering. Press Delete again to confirm. If it was active, Original becomes active.
- **Control+Tab or Escape:** close the list and go back to where you were.

## Settings

F12 opens the settings list. Up and Down move between settings, and Page Up and Page Down change the focused one. F12 or Escape returns you to where you were.

- **REAPER's current track:** follows the script by default. Whenever you move to another track, or into one, it becomes REAPER's last touched track and its only selected track. Leaving the script then finds you on the same track, and so does starting it again. Set it to "left alone" if you'd rather the script didn't change REAPER's track selection.

## Home and End

On some keyboards, Home sits below End. The "Home and End" setting is swapped by default, for those keyboards. Like the arrow keys, the lower key goes down and the upper key goes up:

- **Home** moves down a stop, towards the last item. Shift+Home extends the selection downwards, and Control+Home goes straight to the last item.
- **End** moves up a stop, towards the first item. Shift+End extends the selection upwards, and Control+End goes straight to the first item.

On a standard keyboard, where Home is above End, open the settings list with F12 and change "Home and End" to standard. That reverses all of them.

## Saving

- **When:** your organization is saved automatically after every change. There is no save command.
- **Where:** each plugin type's orderings are kept in one plain-text file in REAPER's resource folder, in `ParameterOrganizer\layouts`. Options, then "Show REAPER resource path in explorer/finder", opens the resource folder.
- **Plugin identity:** plugins are recognised by REAPER's identifier for the plugin type, so renaming an instance on a track doesn't matter.
- **Containers:** a container's own parameters depend on that particular container, so a container's orderings are saved in the project instead. They're kept when you save the project. Effects inside containers use their per-plugin files as usual.
- **Plugin updates:** if an update reorders a plugin's parameters, they're found again by name. A parameter that can't be found at all stays in your layout and says "missing", so your work isn't lost. You can delete a missing parameter.

## Containers

A container appears like an effect, with "container" after its name. Go into it with Right: first come the effects it holds, then your branches, then the container's own unplaced parameters. Containers inside containers work the same way.

## Limitations

- Effects on media items (take FX) aren't included yet.
- Parameter values are read by the effect's position in the chain. After reordering effects while the script is open, press Control+Shift+R.
- Autolabels match whole words only, so "Atk" isn't matched by a branch called "attack". Rename the branch, or the parameter with F2.
- Filtering and sorting work only on the default branch, not inside your own branches.
- Unplaced parameters can't be renamed. Place a parameter in a branch to rename it.
- Branches can't be cut and moved.
- An effect moved to another track is treated as new: it gets its saved layout again (after Control+Shift+R, when moved outside the script), but loses a filter or sort.

## For developers

The tree logic, autolabeling, value search, sorting and filtering, selection, settings, layouts and orderings are plain Lua with no REAPER calls, and are tested outside REAPER:

- `lua tests\run.lua` runs the unit tests.
- `lua tests\smoke_main.lua` runs the whole script against a fake REAPER with a scripted series of key presses, prints everything that would be spoken, then runs a second session to check that saved layouts come back.

The tests are written for Lua 5.4, the version built into REAPER, and also run under Lua 5.5.

## Acknowledgements

The hidden-window approach, as well as the entire parameter reorganization idea, was inspired by [Lo-lo](https://github.com/lo-lo78)'s SpeakParams suite.

## License

Parameter Organizer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the `LICENSE` file for the full text.
