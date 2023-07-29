local json = require("json")
local SaveManager = {}
SaveManager.VERSION = 1.0

SaveManager.Utility = {}


---@class SaveData
---@field game GameSave @Data that is persistent to the run. Starting a new run wipes this data. Affected by Glowing Hourglass.
---@field gameNoBackup GameSave @Data that is persistent to the run. Starting a new run wipes this data. IS NOT AFFECTED by Glowing Hourglass.
---@field hourglassBackup GameSave @A backup of `game` that is not to be edited.
---@field file FileSave @Data that is persistent to the save file. This data is never wiped.

---@class GameSave
---@field run table @Things in this table are persistent throughout the entire run.
---@field floor table @Things in this table are persistent only for the current floor.
---@field room table @Things in this table are persistent only for the current room.

---@class FileSave
---@field unlockApi table @Built in compatibility for UnlockAPI (https://github.com/dsju/unlockapi)
---@field deadSeaScrolls table @Built in support for Dead Sea Scrolls (https://github.com/Meowlala/DeadSeaScrollsMenu)
---@field settings table @Miscellaneous table for anything settings-related.
---@field other table @Miscellaneous table for if you want to use your own unlock system or just need to store random data to the file.


SaveManager.DEFAULT_SAVE = {
    game = {
        run = {},
        floor = {},
        room = {}
    },
    gameNoBackup = {
        run = {},
        floor = {},
        room = {}
    },
    file = {
        unlockApi = {},
        deadSeaScrolls = {},
        settings = {},
        other = {}
    }
}

---Gets a unique string specific to the player. This string never changes.
---@param player EntityPlayer
function SaveManager.Utility.GetPlayerIndex(player)
    return "PLAYER_" .. player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_SAD_ONION):GetSeed()
end
