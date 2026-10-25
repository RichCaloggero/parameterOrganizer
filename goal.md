# Parameter Organizer for Reaper

The goal of this project is to make navigating fx with many parameters more efficient via screen reader.

The idea is to write reaScript in lua which allows the user to organize the parameters into a tree. The tree should be navicable like any standard windows tree widget, via arrow keys.

Another screen reader user has come up with a way of running a lua script in a small or hidden window, and leveraging keyboard control and direct screen reader speech output via the OSARA extension. Please try and find the reference, but I will dig out some code I have on my backup drive for you to review.

## How It Works

When the script is run, it presents a list of all fx parameters by their labels on all tracks. The first implementation should probably work track-by-track, so the list could be a tree:

i- track
    + fx name
        + parameter
        + parameter
        + ...
    + ...
- ...

The user is also presented with another empty tree; navigate between them with control+tab. In this empty tree, the user can either:

- create a branch
- or paste a leaf node (a parameter from the other tree) into a branch
- branches can, of course, be nested

For the first try, the system will create the first two levels for the user:

- track
    + fx ...
- track
+ fx    ...
- ...

The user can then create levels below that inside each fx branch to organize that effect's parameters any way she wishes. For example, I have a stereo phaser that has Q and frequency parameters for each channel. The Q parameters include min and max Q, and attack and release parameters. Similarly for frequency...

With this system, I'm invisioning the user to be able to organize these parameters into a tree to make them easier to navigate instead of having to continually tab through a long list. The exact organization should be up to the user. I would probably organize as follows:

- frequency
    + min   
        + left
        + right
    + max
        + left
        + right
    attack
        + left
        + right
    + release
        + left
        + right
- frequency
    + ...

## Autolabeling

Consider the previous phaser example tree. Assume the jsfx that implements the effect has a parameter labeled "left Q attack". When this is pasted into the resultant tree, the label will get rewritten based on the parent branch names. In this example, the parent branches are labeled Q, and attack, so these words are removed from the original parameter's label leving either "left" or "right", depending on which one is being pasted. For this to work well, the user would need to choose branch names which correspond well to the original labels. In addition, the user could relabel the parameter via f2 after pasting if the autolabel is insufficient or confusing.

## Keyboard commands

- up and down arrows move through a tree level
- left and right arrows open a level and focus the first item within the new level (standard tree widgets make this a two step process, but to me it makes sense to combine behaviors)
- control+c copies a parameter
- control+v pastes a parameter
- f2 creates a branch and prompts for a branch name, or ralabels a leaf node

## After version 0.9

Version 0.9 used two trees. From here on there is only one tree, and organizing happens inside it.

- The script starts as before: tracks, the effects on each track, and each effect's parameters in their original order. Call that list of parameters the default branch.
- Small plugins can be used as they are; organizing is optional.
- In the default branch only:
    + control+g sorts the parameters in natural order, so band1, band2, band10 always sort that way and never band1, band10, band2
    + control+f filters the parameters by a word or phrase
    + control+r reverts to the original order with no filter
- These keys, like the others, should later be redefinable in the settings list.
- Branches the user creates always sit at the top of the effect, ahead of the unplaced parameters. Sorting and filtering never move them.
- Cutting and pasting into a chosen position only happens inside branches the user creates. The default branch is never rearranged by hand.
- Workflow: filter and/or sort to bring a group together, select the whole group, cut it, create a branch (focus moves to it), move into it, and paste.
- Selection works like a standard Windows list: Shift with the arrows extends a selection, Control with the arrows moves without changing it, and Control+Space toggles the focused item. Control+A selects every parameter at the current level, skipping branches.
- Value changes: Page Up and Page Down make small steps, Shift+Page Up and Shift+Page Down make large steps, and Control+Page Up and Control+Page Down go to the maximum and minimum. Page Up and Page Down are never swapped.
- Later ideas: a "start over" command for an effect's organization, and a list of named organizations to choose from, add to, or delete from.

