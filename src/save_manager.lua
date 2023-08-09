-- Check out everything here: https://github.com/maya-bee/IsaacSaveManager

local json = require("json")
local game = Game()
local SaveManager = {}
SaveManager.VERSION = 1.03

SaveManager.Utility = {}

-- Used in the DEFAULT_SAVE table as a key with the value being the default save data for a player in this save type.
SaveManager.PLAYER_DEFAULT_SAVE_KEY = "__DEFAULT_PLAYER"

local modReference
local loadedData = false
local dataCache = {}
local hourglassBackup = {}
local shouldRestoreOnUse = false
local skipNextRoomClear = false
local skipNextLevelClear = false
local inRunButNotLoaded = true

SaveManager.Utility.ERROR_MESSAGE_FORMAT = "[IsaacSaveManager:%s] ERROR: %s (%s)\n"
SaveManager.Utility.WARNING_MESSAGE_FORMAT = "[IsaacSaveManager:%s] WARNING: %s (%s)\n"
SaveManager.Utility.ErrorMessages = {
    NOT_INITIALIZED = "The save manager cannot be used without initializing it first!",
    DATA_NOT_LOADED = "An attempt to use save data was made before it was loaded!",
    BAD_DATA = "An attempt to save invalid data was made!",
    BAD_DATA_WARNING = "Data saved with warning!",
    COPY_ERROR = "An error was made when copying from cached data to what would be saved! This could be due to a circular reference."
}
SaveManager.Utility.JsonIncompatibilityType = {
    SPARSE_ARRAY = "Sparse arrays, or arrays with gaps between indexes, will fill gaps with null when encoded.",
    INVALID_KEY_TYPE = "Tables that have non-string or non-integer (decimal or non-number) keys cannot be encoded.",
    MIXED_TABLES = "Tables with mixed key types cannot be encoded.",
    NAN_VALUE = "Tables with invalid numbers (NaN, -inf, inf) cannot be encoded.",
    NO_FUNCTIONS = "Tables containing functions cannot be encoded.",
    CIRCULAR_TABLE = "Tables that contain themselves cannot be encoded.",
}

---@enum SaveManager.Utility.CustomCallback
SaveManager.Utility.CustomCallback = {
    PRE_DATA_SAVE = "ISAACSAVEMANAGER_PRE_DATA_SAVE",
    POST_DATA_LOAD = "ISAACSAVEMANAGER_POST_DATA_LOAD",
}

SaveManager.Utility.ValidityState = {
    VALID = 0,
    VALID_WITH_WARNING = 1,
    INVALID = 2,
}

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


-- You can edit what is inside of these tables, but changing the overall structure of this table will break things.
-- HOWEVER, you MAY remove any table with [SaveManager.PLAYER_DEFAULT_SAVE_KEY] as the key!
SaveManager.DEFAULT_SAVE = {
    game = {
        run = {
            [SaveManager.PLAYER_DEFAULT_SAVE_KEY] = {}
        },
        floor = {
            [SaveManager.PLAYER_DEFAULT_SAVE_KEY] = {}
        },
        room = {
            [SaveManager.PLAYER_DEFAULT_SAVE_KEY] = {}
        }
    },
    gameNoBackup = {
        run = {
            [SaveManager.PLAYER_DEFAULT_SAVE_KEY] = {}
        },
        floor = {
            [SaveManager.PLAYER_DEFAULT_SAVE_KEY] = {}
        },
        room = {
            [SaveManager.PLAYER_DEFAULT_SAVE_KEY] = {}
        }
    },
    file = {
        unlockApi = {},
        deadSeaScrolls = {},
        settings = {},
        other = {}
    }
}

--[[
    ###########################
    #  UTILITY METHODS START  #
    ###########################
]]

function SaveManager.Utility.SendError(msg)
    local _, traceback = pcall(error, "", 4) -- 4 because it is 4 layers deep
    Isaac.ConsoleOutput(SaveManager.Utility.ERROR_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg, traceback))
    Isaac.DebugString(SaveManager.Utility.ERROR_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg, traceback))
end

function SaveManager.Utility.SendWarning(msg)
    local _, traceback = pcall(error, "", 4) -- 4 because it is 4 layers deep
    Isaac.ConsoleOutput(SaveManager.Utility.WARNING_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg, traceback))
    Isaac.DebugString(SaveManager.Utility.WARNING_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg, traceback))
end

function SaveManager.Utility.IsCircular(tab, traversed)
    traversed = traversed or {}

    if traversed[tab] then
        return true
    end

    traversed[tab] = true

    for _, v in pairs(tab) do
        if type(v) == "table" then
            if SaveManager.Utility.IsCircular(v, traversed) then
                return true
            end
        end
    end

    return false
end

function SaveManager.Utility.DeepCopy(tab)
    if type(tab) ~= "table" then
        return tab
    end

    local final = setmetatable({}, getmetatable(tab))
    for i, v in pairs(tab) do
        final[SaveManager.Utility.DeepCopy(i)] = SaveManager.Utility.DeepCopy(v)
    end

    return final
end

---Gets a unique string specific to the player. This string never changes.
---@param player EntityPlayer
function SaveManager.Utility.GetPlayerIndex(player)
    return "PLAYER_" .. player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_SAD_ONION):GetSeed()
end

---Patches a save file with the default save data.
function SaveManager.Utility.PatchSaveFile(deposit, source, keepDefaultSaveKey)
    source = source or SaveManager.DEFAULT_SAVE
    for i, v in pairs(source) do
        if i == SaveManager.PLAYER_DEFAULT_SAVE_KEY and not keepDefaultSaveKey then
            goto continue
        end

        if deposit[i] ~= nil then
            if type(v) == "table" then
                if type(deposit[i]) ~= "table" then
                    deposit[i] = {}
                end

                deposit[i] = SaveManager.Utility.PatchSaveFile(deposit[i], v, keepDefaultSaveKey)
            end
        else
            if type(v) == "table" then
                if type(deposit[i]) ~= "table" then
                    deposit[i] = {}
                end

                deposit[i] = SaveManager.Utility.PatchSaveFile({}, v, keepDefaultSaveKey)
            end
        end

        ::continue::
    end

    return deposit
end

local function isSparseArray(tab)
    local max = 0
    for i in pairs(tab) do
        if type(i) ~= "number" then
            return false
        end

        if i > max then
            max = i
        end
    end

    return max ~= #tab
end

-- Recursively validates if a table can be encoded into valid JSON.
-- Returns 0 if it can be encoded, 1 if it can but has a warning, and 2 if item cannot. If 1 or 2, it will also return a message.
function SaveManager.Utility.ValidateForJson(tab)
    local hasWarning

    -- check for mixed table
    local indexType
    for index in pairs(tab) do
        if not indexType then
            indexType = type(index)
        end

        if type(index) ~= indexType then
            return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.MIXED_TABLES
        end

        if type(index) ~= "string" and type(index) ~= "number" then
            return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE
        end

        if type(index) == "number" and math.floor(index) ~= index then
            return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE
        end
    end

    -- check for sparse array
    if isSparseArray(tab) then
        hasWarning = SaveManager.Utility.JsonIncompatibilityType.SPARSE_ARRAY
    end

    if SaveManager.Utility.IsCircular(tab) then
        return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.CIRCULAR_TABLE
    end

    for _, value in pairs(tab) do
        -- check for NaN and infinite values
        -- http://lua-users.org/wiki/InfAndNanComparisons
        if type(value) == "number" then
            if value == math.huge or value == -math.huge or value ~= value then
                return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.NAN_VALUE
            end
        end

        if type(value) == "function" then
            return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.NO_FUNCTIONS
        end

        if type(value) == "table" then
            local valid, error = SaveManager.Utility.ValidateForJson(value)
            if valid == SaveManager.Utility.ValidityState.INVALID then
                return valid, error
            elseif valid == SaveManager.Utility.ValidityState.VALID_WITH_WARNING then
                hasWarning = error
            end
        end

    end

    if hasWarning then
        return SaveManager.Utility.ValidityState.VALID_WITH_WARNING, hasWarning
    end

    return SaveManager.Utility.ValidityState.VALID
end

function SaveManager.Utility.RunCallback(callbackId, ...)
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    local id = modReference.__SAVEMANAGER_UNIQUE_KEY .. callbackId
    local callbacks = Isaac.GetCallbacks(id)
    table.sort(callbacks, function (a, b)
        return a.Priority < b.Priority
    end)

    for _, callback in ipairs(callbacks) do
        callback.Function(callback.Mod, ...)
    end
end

--[[
    ########################
    #  CORE METHODS START  #
    ########################
]]

function SaveManager.IsLoaded()
    return loadedData
end

---@param callbackId SaveManager.Utility.CustomCallback
---@param callback function
function SaveManager.AddCallback(callbackId, callback)
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    local key = modReference.__SAVEMANAGER_UNIQUE_KEY
    modReference:AddCallback(key .. callbackId, callback)
end

-- Saves save data to the file.
function SaveManager.Save()

    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    -- Create backup
    -- pcall deep copies the data to prevent errors from being thrown
    -- errors thrown in unload callback crash isaac

    local success, finalData = pcall(SaveManager.Utility.DeepCopy, dataCache)

    if success then
        finalData = SaveManager.Utility.PatchSaveFile(finalData, SaveManager.DEFAULT_SAVE)
    else
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.COPY_ERROR)
        return
    end

    local success2, backupData = pcall(SaveManager.Utility.DeepCopy, hourglassBackup)

    if success2 then
        finalData.hourglassBackup = backupData
    else
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.COPY_ERROR)
        return
    end

    SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.PRE_DATA_SAVE, finalData)

    -- validate data
    local valid, msg = SaveManager.Utility.ValidateForJson(finalData)
    if valid == SaveManager.Utility.ValidityState.INVALID then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.BAD_DATA)
        SaveManager.Utility.SendError(msg)
        return
    elseif valid == SaveManager.Utility.ValidityState.VALID_WITH_WARNING then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.BAD_DATA_WARNING)
        SaveManager.Utility.SendWarning(msg)
    end

    modReference:SaveData(json.encode(finalData))
end

-- Restores the game save with the data in the hourglass backup.
function SaveManager.HourglassRestore()
    if shouldRestoreOnUse then
        skipNextRoomClear = true
        local newData = SaveManager.Utility.DeepCopy(hourglassBackup)
        dataCache.game = SaveManager.Utility.PatchSaveFile(newData, SaveManager.DEFAULT_SAVE.game)
    end
end

-- Loads save data from the file, overwriting what is already loaded.
function SaveManager.Load()
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    local saveData = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE)

    if modReference:HasData() then
        local data = json.decode(modReference:LoadData())
        saveData = SaveManager.Utility.PatchSaveFile(data, SaveManager.DEFAULT_SAVE)
    end

    dataCache = saveData
    hourglassBackup = SaveManager.Utility.DeepCopy(dataCache.hourglassBackup)

    loadedData = true
    inRunButNotLoaded = false

    SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.POST_DATA_LOAD, dataCache)
end

--[[
    ##########################
    #  CORE CALLBACKS START  #
    ##########################
]]

local function onGameStart(_, player)
    local newGame = game:GetFrameCount() == 0
    local playerIndex = SaveManager.Utility.GetPlayerIndex(player)

    skipNextLevelClear = true
    skipNextRoomClear = true

    SaveManager.Load()

    if newGame then
        dataCache.game = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
        dataCache.gameNoBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup)
        hourglassBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
    end

    -- provide an array of keys to grab the target table from the original
    local function reconstructHistory(original, historyArray, iter)
        iter = iter or 1
        local key = historyArray[iter]
        if not key then
            return original
        end

        for i, v in pairs(original) do
            if i == key then
                if type(v) == "table" then
                    return reconstructHistory(v, historyArray, iter + 1)
                end
            end
        end
    end

    -- go through the default save, look for default player keys, and copy those in the same spot in the target save
    local function implementPlayerKeys(tab, target, history)
        history = history or {}
        for i, v in pairs(tab) do
            if i == SaveManager.PLAYER_DEFAULT_SAVE_KEY then
                local targetTable = reconstructHistory(target, history)
                if targetTable then
                    -- create or patch the target table with the default save
                    targetTable[playerIndex] = SaveManager.Utility.PatchSaveFile(targetTable[playerIndex] or {}, SaveManager.Utility.DeepCopy(v))
                    targetTable[i] = nil
                end
            elseif type(v) == "table" then
                table.insert(history, i)
                implementPlayerKeys(v, target, history)
                table.remove(history)
            end
        end
        return target
    end

    implementPlayerKeys(SaveManager.DEFAULT_SAVE.game, dataCache.game)
    implementPlayerKeys(SaveManager.DEFAULT_SAVE.gameNoBackup, dataCache.gameNoBackup)
end

local function detectLuamod()
    if game:GetFrameCount() > 0 then
        if not loadedData and inRunButNotLoaded then
            SaveManager.Load()
            inRunButNotLoaded = false
            shouldRestoreOnUse = true
        end
    end
end

local function postNewRoom()
    if not skipNextRoomClear then
        hourglassBackup.run = SaveManager.Utility.DeepCopy(dataCache.game.run)
        hourglassBackup.room = SaveManager.Utility.DeepCopy(dataCache.game.room)
        dataCache.game.room = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game.room)
        dataCache.gameNoBackup.room = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup.room)

        SaveManager.Save()
        shouldRestoreOnUse = true
    end

    skipNextRoomClear = false
end

local function postNewLevel()
    if not skipNextLevelClear then
        hourglassBackup.run = SaveManager.Utility.DeepCopy(dataCache.game.run)
        hourglassBackup.floor = SaveManager.Utility.DeepCopy(dataCache.game.floor)
        dataCache.game.floor = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game.floor)
        dataCache.gameNoBackup.floor = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup.floor)

        SaveManager.Save()
        shouldRestoreOnUse = true
    end

    skipNextLevelClear = false
end

local function preGameExit()
    SaveManager.Save()
    loadedData = false
    inRunButNotLoaded = false
    shouldRestoreOnUse = false
end

--[[
    ##########################
    #  INITIALIZATION LOGIC  #
    ##########################
]]

-- Initializes the save manager.
---@param mod table @The reference to your mod. This is the table that is returned when you call `RegisterMod`.
function SaveManager.Init(mod)
    modReference = mod

    modReference:AddCallback(ModCallbacks.MC_USE_ITEM, SaveManager.HourglassRestore, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
    modReference:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, onGameStart) -- it runs before the game started callback lol
    modReference:AddPriorityCallback(ModCallbacks.MC_POST_PLAYER_RENDER, CallbackPriority.IMPORTANT, detectLuamod) -- want to run as early as possible
    modReference:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, postNewRoom)
    modReference:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, postNewLevel)
    modReference:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, preGameExit)

    -- used to detect if an unloaded mod is this mod for when saving for luamod
    modReference.__SAVEMANAGER_UNIQUE_KEY = ("%s-%s"):format(Random(), Random())
    modReference:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function (_, modToUnload)
        if modToUnload.__SAVEMANAGER_UNIQUE_KEY and modToUnload.__SAVEMANAGER_UNIQUE_KEY == modReference.__SAVEMANAGER_UNIQUE_KEY then
            if loadedData then
                SaveManager.Save()
            end
        end
    end)
end

--[[
    ########################
    #  SAVE METHODS START  #
    ########################
]]

-- Returns the entire save table, including the file save.
function SaveManager.GetEntireSave()
    return dataCache
end

---@param player EntityPlayer? @If provided, it'll return a player specific save within the run save.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetRunSave(player, noHourglass)
    noHourglass = noHourglass or false
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    if noHourglass then
        if player then
            local data = dataCache.gameNoBackup.run[SaveManager.Utility.GetPlayerIndex(player)]
            if data == nil then
                local defaultPlayerSave = SaveManager.DEFAULT_SAVE.gameNoBackup.run[SaveManager.PLAYER_DEFAULT_SAVE_KEY]
                dataCache.gameNoBackup.run[SaveManager.Utility.GetPlayerIndex(player)] = SaveManager.Utility.DeepCopy(defaultPlayerSave)
            end

            return dataCache.gameNoBackup.run[SaveManager.Utility.GetPlayerIndex(player)]
        end

        return dataCache.gameNoBackup.run
    else
        if player then
            local data = dataCache.game.run[SaveManager.Utility.GetPlayerIndex(player)]
            if data == nil then
                local defaultPlayerSave = SaveManager.DEFAULT_SAVE.game.run[SaveManager.PLAYER_DEFAULT_SAVE_KEY]
                dataCache.game.run[SaveManager.Utility.GetPlayerIndex(player)] = SaveManager.Utility.DeepCopy(defaultPlayerSave)
            end

            return dataCache.game.run[SaveManager.Utility.GetPlayerIndex(player)]
        end

        return dataCache.game.run
    end
end

---@param player EntityPlayer? @If provided, it'll return a player specific save within the run save.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetFloorSave(player, noHourglass)
    noHourglass = noHourglass or false
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    if noHourglass then
        if player then
            local data = dataCache.gameNoBackup.floor[SaveManager.Utility.GetPlayerIndex(player)]
            if data == nil then
                local defaultPlayerSave = SaveManager.DEFAULT_SAVE.gameNoBackup.floor[SaveManager.PLAYER_DEFAULT_SAVE_KEY]
                dataCache.gameNoBackup.floor[SaveManager.Utility.GetPlayerIndex(player)] = SaveManager.Utility.DeepCopy(defaultPlayerSave)
            end

            return dataCache.gameNoBackup.floor[SaveManager.Utility.GetPlayerIndex(player)]
        end

        return dataCache.gameNoBackup.floor
    else
        if player then
            local data = dataCache.game.floor[SaveManager.Utility.GetPlayerIndex(player)]
            if data == nil then
                local defaultPlayerSave = SaveManager.DEFAULT_SAVE.game.floor[SaveManager.PLAYER_DEFAULT_SAVE_KEY]
                dataCache.game.floor[SaveManager.Utility.GetPlayerIndex(player)] = SaveManager.Utility.DeepCopy(defaultPlayerSave)
            end

            return dataCache.game.floor[SaveManager.Utility.GetPlayerIndex(player)]
        end

        return dataCache.game.floor
    end
end

---@param player EntityPlayer? @If provided, it'll return a player specific save within the run save.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetRoomSave(player, noHourglass)
    noHourglass = noHourglass or false
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    if noHourglass then
        if player then
            local data = dataCache.gameNoBackup.room[SaveManager.Utility.GetPlayerIndex(player)]
            if data == nil then
                local defaultPlayerSave = SaveManager.DEFAULT_SAVE.gameNoBackup.room[SaveManager.PLAYER_DEFAULT_SAVE_KEY]
                dataCache.gameNoBackup.room[SaveManager.Utility.GetPlayerIndex(player)] = SaveManager.Utility.DeepCopy(defaultPlayerSave)
            end

            return dataCache.gameNoBackup.room[SaveManager.Utility.GetPlayerIndex(player)]
        end

        return dataCache.gameNoBackup.room
    else
        if player then
            local data = dataCache.game.room[SaveManager.Utility.GetPlayerIndex(player)]
            if data == nil then
                local defaultPlayerSave = SaveManager.DEFAULT_SAVE.game.room[SaveManager.PLAYER_DEFAULT_SAVE_KEY]
                dataCache.game.room[SaveManager.Utility.GetPlayerIndex(player)] = SaveManager.Utility.DeepCopy(defaultPlayerSave)
            end

            return dataCache.game.room[SaveManager.Utility.GetPlayerIndex(player)]
        end

        return dataCache.game.room
    end
end

---Please note that this is essentially a normal table with the connotation of being used with UnlockAPI.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetUnlockAPISave()
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    return dataCache.file.unlockApi
end

---Please note that this is essentially a normal table with the connotation of being used with Dead Sea Scrolls (DSS).
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetDeadSeaScrollsSave()
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    return dataCache.file.deadSeaScrolls
end

---Please note that this is essentially a normal table with the connotation of being used to store settings.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetSettingsSave()
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    return dataCache.file.settings
end

---Gets the "other" save data within the file save. Basically just a table you can put anything it.
function SaveManager.GetPersistentSave()
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return
    end

    return dataCache.file.other
end

return SaveManager