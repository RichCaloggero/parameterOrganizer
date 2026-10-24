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


