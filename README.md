# IsaacSaveManager
 A save manager for Isaac that requires no other dependencies.

## Features

- Data validator that prevents corrupt save data.
- Saves specific to the room, floor, and run, along with saves that persist for the entire file.
- Player, familiar, pickup, slot, and grid specific saves.
- Different saves depending on if you want the data to be affected by Glowing Hourglass or not.
- Easy to understand system to make default data.
- Intuitive as heck!

## Installation

1. Download the [latest release, found here.](https://github.com/catinsurance/IsaacSaveManager/releases)
2. Place the file anywhere in your mod. I recommend putting it in a neatly organized place, such as in a folder named "utility" that's within a greater "scripts" folder.
3. In your `main.lua` file, `include` the file.
```lua
local mod = RegisterMod("My spectacular mod", 1)
local saveManager = include("path.to.save.manager") -- the path to the save manager, with different directories/folders separated by dots
```
4. Initialize the save manager
```lua
saveManager.Init(mod)
```

## To find out how to use, please open the wiki
https://github.com/catinsurance/IsaacSaveManager/wiki
