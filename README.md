# Parameter Organizer for REAPER

Parameter Organizer is a REAPER script for screen reader users. It lets you browse every effect parameter in your project as a tree, change values from the keyboard, and organize a plugin's parameters into branches of your own design, so that a plugin with dozens of parameters becomes quick to navigate.

Everything is spoken through OSARA. The script runs in a tiny hidden window that only captures the keyboard.

## What it does

- **Source tree:** every track that has effects (the master track first), each effect on it, and each effect's parameters. Effects inside REAPER 7 containers are shown nested inside their container.
- **Organized tree:** the same tracks and effects, but each effect starts empty. You create branches inside it and paste parameters into them. For example, a stereo phaser could become frequency, then min and max, then left and right.
- **Autolabels:** a parameter pasted into branches is renamed by removing the words of the branches above it. "left Q attack", pasted under the branches Q and attack, becomes simply "left".
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

1. Press your shortcut. You hear "Parameter organizer, source tree".
2. Use Down to reach a track, Right to go into it, Right again to go into an effect, then Up and Down to hear its parameters and their values.
3. Press Control+Tab to switch to the organized tree. Go into the same track and effect with Right. An effect you haven't organized yet says "empty".
4. Press Control+N, type a branch name such as "frequency", and press Enter.
5. Press Control+Tab to go back to the source tree, find a parameter, and press Control+C.
6. Press Control+Tab again, press Right to go inside your new branch, and press Control+V. The parameter is placed there, with its autolabel.
7. Press Escape to quit. Next time, your branches are still there, for every copy of that plugin.

## Keyboard

### Moving around, in either tree

- **Up and Down:** the previous or next item at the same level. Branches, tracks and effects say "collapsed", which means you can go into them with Right. Parameters say their value.
- **Right:** go into a track, effect, container or branch, and hear its first item. An empty one says "empty".
- **Left:** close the current level and go back to its parent.
- **Home and End:** the first or last item at the current level. By default these are swapped: see "Home and End" below.
- **A letter or digit:** the next item at this level starting with it.
- **Control+Tab:** switch between the source tree and the organized tree. Each tree remembers where you were.
- **F5:** refresh both trees from the project, after adding, removing or moving effects.
- **F12:** open the settings list.
- **Escape:** quit.

### Changing values, on any parameter in either tree

- **Shift+Up and Shift+Down:** a small step up or down. Each step always changes what the plugin displays, so a selector such as a reverb type moves one choice at a time.
- **Page Up and Page Down:** a large step, about a tenth of the range.
- **Shift+Home and Shift+End:** the minimum or the maximum. By default, Shift+Home is the minimum.
- **Enter:** type an exact value in the plugin's own units, for example "2500", "2.5 kHz" or "-6". For selectors, type the word shown, for example "Plate".
- REAPER's own Bypass and Delta parameters, which every effect has, work as on/off switches: the upward keys turn them on, and the downward keys turn them off.

Value changes are not added to REAPER's undo history.

### Organizing, in the organized tree

- **Control+N:** create a branch at the current level, right after the focused item. To create a branch inside another branch or inside an effect, go into it first with Right.
- **Control+C:** copy the focused parameter. This works in either tree.
- **Control+X:** cut the focused parameter. It stays where it is until you paste it.
- **Control+V:** paste at the current level, right after the focused item. Each parameter appears only once in the organized tree, so pasting a parameter that's already placed moves it, and you hear where it came from. A parameter can only be pasted inside its own effect.
- **F2:** rename the focused branch or parameter. Clearing a parameter's name gives it back its autolabel.
- **Delete:** remove a parameter from the organized tree. On a branch with anything in it, you're asked first: press Delete again to confirm.

Tracks and effects mirror your project, so they can't be renamed or deleted here.

### In the settings list

The settings list uses the same keys: Up and Down move between settings, and Shift+Up, Shift+Down, Page Up and Page Down change the focused one. F12 or Escape returns you to where you were.

## Home and End

On some keyboards, Home sits below End. The "Home and End" setting is swapped by default, for those keyboards. Like the arrow keys, the lower key goes down and the upper key goes up:

- **Home** moves to the last item, and Shift+Home sets the minimum.
- **End** moves to the first item, and Shift+End sets the maximum.

On a standard keyboard, where Home is above End, open the settings list with F12 and change "Home and End" to standard. That reverses both.

## In the source tree

Each parameter in the source tree also tells you where it's placed in the organized tree, after its value. For example, "placed in Q, attack", or "unplaced". This helps you find what's still left to organize.

## Saving

- **When:** your organization is saved automatically after every change. There is no save command.
- **Where:** each plugin type's layout is a plain-text file in REAPER's resource folder, in `ParameterOrganizer\layouts`. Options, then "Show REAPER resource path in explorer/finder", opens the resource folder.
- **Plugin identity:** plugins are recognised by REAPER's identifier for the plugin type, so renaming an instance on a track doesn't matter.
- **Containers:** a container's own parameters depend on that particular container, so a container's layout is saved in the project instead. It's kept when you save the project. Effects inside containers use their per-plugin files as usual.
- **Plugin updates:** if an update reorders a plugin's parameters, they're found again by name. A parameter that can't be found at all stays in your layout and says "missing", so your work isn't lost. You can delete a missing parameter.

## Containers

A container appears like an effect. Go into it with Right: first come the effects it holds, then the container's own parameters. Containers inside containers work the same way. In the organized tree, your branches inside a container always come after the effects it holds.

## Limitations

- Effects on media items (take FX) aren't included yet.
- Parameter values are read by the effect's position in the chain. After reordering effects while the script is open, press F5.
- Autolabels match whole words only, so "Atk" isn't matched by a branch called "attack". Rename the branch, or the parameter with F2.
- If an effect is moved to another track while the script is open, the organized tree treats it as new, and it gets its saved layout again after F5.

## For developers

The tree logic, autolabeling, value search, settings and layouts are plain Lua with no REAPER calls, and are tested outside REAPER:

- `lua tests\run.lua` runs the unit tests.
- `lua tests\smoke_main.lua` runs the whole script against a fake REAPER with a scripted series of key presses, prints everything that would be spoken, then runs a second session to check that saved layouts come back.

The tests are written for Lua 5.4, the version built into REAPER, and also run under Lua 5.5.

## Acknowledgements

The hidden-window approach, as well as the entire parameter reorganization idea, was inspired by [Lo-lo](https://github.com/lo-lo78)'s SpeakParams suite.

## License

Parameter Organizer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the `LICENSE` file for the full text.
