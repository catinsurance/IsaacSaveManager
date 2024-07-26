-- Check out everything here: https://github.com/maya-bee/IsaacSaveManager

local game = Game()
local SaveManager = {}
SaveManager.VERSION = 2

SaveManager.Utility = {}

-- Used in the DEFAULT_SAVE table as a key with the value being the default save data for a player in this save type.

---@enum ConstructSaveKeys
SaveManager.ConstructSaveKeys = {
    GLOBAL = "__CONSTRUCT_GLOBAL",  --Prepares default non-entity data
    PLAYER = "__CONSTRUCT_PLAYER",  --Prepares default player-specfic data
    FAMILIAR = "__CONSTRUCT_FAMILIAR", --Prepares default familiar-specfic data
    PICKUP = "__CONSTRUCT_PICKUP",  --Prepares default pickup-specfic data
    SLOT = "__CONSTRUCT_SLOT",      --Prepares default slot-specfic data
}

---@enum DefaultSaveKeys
SaveManager.DefaultSaveKeys = {
    PLAYER = "__DEFAULT_PLAYER",
    FAMILIAR = "__DEFAULT_FAMILIAR",
    PICKUP = "__DEFAULT_PICKUP",
    SLOT = "__DEFAULT_SLOT",
    GLOBAL = "__DEFAULT_GLOBAL",
}

local modReference
local json
local loadedData = false
local skipFloorReset = false
local skipRoomReset = false
local shouldRestoreOnUse = true
local myosotisCheck = false
local storePickupDataOnGameExit = false
---@class SaveData
local dataCache = {}
---@class GameSave
local hourglassBackup = {}
local inRunButNotLoaded = true

SaveManager.Utility.ERROR_MESSAGE_FORMAT = "[IsaacSaveManager:%s] ERROR: %s (%s)\n"
SaveManager.Utility.WARNING_MESSAGE_FORMAT = "[IsaacSaveManager:%s] WARNING: %s (%s)\n"
SaveManager.Utility.ErrorMessages = {
    NOT_INITIALIZED = "The save manager cannot be used without initializing it first!",
    DATA_NOT_LOADED = "An attempt to use save data was made before it was loaded!",
    BAD_DATA = "An attempt to save invalid data was made!",
    BAD_DATA_WARNING = "Data saved with warning!",
    COPY_ERROR =
    "An error was made when copying from cached data to what would be saved! This could be due to a circular reference.",
    INVALID_ENTITY_TYPE = "The save manager cannot support non-persistent entities!",
    INVALID_TYPE_WITH_SAVE =
    "This entity type does not support this save data as it does not persist between floors/move between rooms."
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
---@field gameNoBackup GameSave @Data that is persistent to the run. Starting a new run wipes this data. IS NOT AFFECTED by Glowing Hourglass. Only non-entity and player data is populated here.
---@field hourglassBackup GameSave @A backup of `game` that is not to be edited.
---@field file FileSave @Data that is persistent to the save file. This data is never wiped.

---@class GameSave
---@field run table @Things in this table are persistent throughout the entire run.
---@field floor table @Things in this table are persistent only for the current floor.
---@field roomFloor table @Things in this table are persistent for the current floor and separates data by array of ListIndex.
---@field room table @Things in this table are persistent only for the current room.
---@field pickup PickupSave @Specialized save for pickup data. Not available in the non-hourglass-affected save.

---@class PickupSave
---@field floor table @Things in this table are persistent for the current floor and the first room of the next floor.
---@field treasureRoom table @Things in this table are persistent for the entire run, meant for when you re-visit Treasure Room in the Ascent
---@field bossRoom table @Things in this table are persistent for the entire run, meant for when you re-visit Boss Room in the Ascent

---@class FileSave
---@field unlockApi table @Built in compatibility for UnlockAPI (https://github.com/dsju/unlockapi)
---@field deadSeaScrolls table @Built in support for Dead Sea Scrolls (https://github.com/Meowlala/DeadSeaScrollsMenu)
---@field settings table @Miscellaneous table for anything settings-related.
---@field other table @Miscellaneous table for if you want to use your own unlock system or just need to store random data to the file.

SaveManager.DEFAULT_SAVE_CONSTRUCTOR = {
    run = {},
    floor = {},
    room = {},
}

---You can edit what is inside of these tables, but changing the overall structure of this table will break things.
---@class SaveData
SaveManager.DEFAULT_SAVE = {
    game = {
        run = {},
        floor = {},
        roomFloor = {},
        room = {},
        pickup = {
            treasureRoom = {},
            bossRoom = {},
            floor = {}
        }
    },
    gameNoBackup = {
        run = {},
        floor = {},
        roomFloor = {},
        room = {}
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

SaveManager.Debug = true

function SaveManager.Utility.SendError(msg)
    local _, traceback = pcall(error, "", 4) -- 4 because it is 4 layers deep
    Isaac.ConsoleOutput(SaveManager.Utility.ERROR_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg,
        traceback))
    Isaac.DebugString(SaveManager.Utility.ERROR_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg,
        traceback))
end

function SaveManager.Utility.SendWarning(msg)
    local _, traceback = pcall(error, "", 4) -- 4 because it is 4 layers deep
    Isaac.ConsoleOutput(SaveManager.Utility.WARNING_MESSAGE_FORMAT:format(modReference and modReference.Name or "???",
        msg, traceback))
    Isaac.DebugString(SaveManager.Utility.WARNING_MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg,
        traceback))
end

---A wrap for `print` that only triggers if `SaveManager.Debug` is set to `true`.
function SaveManager.Utility.SendDebugMessage(...)
    if SaveManager.Debug then
        print(...)
    end
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
        final[i] = SaveManager.Utility.DeepCopy(v)
    end

    return final
end

---Checks if the provided string is a default key
---@param key string
function SaveManager.Utility.IsDefaultSaveKey(key)
    for _, keyName in pairs(SaveManager.DefaultSaveKeys) do
        if keyName == key then
            return true
        end
    end
    return false
end

---Checks if the provided string is a "construct" key for loading default data.
---@param key string
function SaveManager.Utility.IsConstructSaveKey(key)
    for _, keyName in pairs(SaveManager.ConstructSaveKeys) do
        if keyName == key then
            return true
        end
    end
    return false
end

---Gets the default save key matching with the entity's type.
---@param ent? Entity | Vector
function SaveManager.Utility.GetDefaultSaveKey(ent)
    local typeToName = {
        [EntityType.ENTITY_PLAYER] = "__DEFAULT_PLAYER",
        [EntityType.ENTITY_FAMILIAR] = "__DEFAULT_FAMILIAR",
        [EntityType.ENTITY_PICKUP] = "__DEFAULT_PICKUP",
        [EntityType.ENTITY_SLOT] = "__DEFAULT_SLOT",
    }
    local key
    if ent then
        if type(ent) == "userdata" then

        else
            key = typeToName[ent.Type]
        end
    else
        key = "__DEFAULT_GLOBAL"
    end
    return key
end

---Gets a unique string as an identifier for the entity in the save data.
---@param ent? Entity | Vector
function SaveManager.Utility.GetSaveIndex(ent)
    local typeToName = {
        [EntityType.ENTITY_PLAYER] = "PLAYER_",
        [EntityType.ENTITY_FAMILIAR] = "FAMILIAR_",
        [EntityType.ENTITY_PICKUP] = "PICKUP_",
        [EntityType.ENTITY_SLOT] = "SLOT_",
    }
    local name
    local identifier
    if ent and getmetatable(ent).__type:find("Entity") then
        if typeToName[ent.Type] then
            name = typeToName[ent.Type]
        end
        identifier = GetPtrHash(ent)
        if ent.Type == EntityType.ENTITY_PLAYER then
            local player = ent:ToPlayer()
            ---@cast player EntityPlayer

            identifier = table.concat({ player:GetCollectibleRNG(1):GetSeed(), player:GetCollectibleRNG(2):GetSeed() },
                "_")
        elseif ent.Type == EntityType.ENTITY_FAMILIAR or ent.Type == EntityType.ENTITY_SLOT then
            identifier = ent.InitSeed
        end
    elseif not ent then
        name = "GLOBAL"
        identifier = ""
    elseif ent and getmetatable(ent).__type == "Vector" then
        ---@cast ent Vector
        name = "GRID_"
        identifier = game:GetRoom():GetGridIndex(ent)
    end
    return name .. identifier
end

---Returns a modified version of `deposit` that has the same data that `source` has. Data present in `deposit` but not `source` is unmodified.
---
---Is mostly used with `deposit` as an empty table and `source` the default save data to overrite existing data with the default data.
---@param deposit table
---@param source table
function SaveManager.Utility.PatchSaveFile(deposit, source)
    for i, v in pairs(source) do
        if i == "roomSave" then goto continue end --No default room-specific saves.
        if SaveManager.Utility.IsDefaultSaveKey(i) then
            SaveManager.Utility.PatchSaveFile(deposit, v)
        elseif type(v) == "table" then
            if type(deposit[i]) ~= "table" then
                deposit[i] = {}
            end

            deposit[i] = SaveManager.Utility.PatchSaveFile(deposit[i] ~= nil and deposit[i] or {}, v)
        else
            deposit[i] = v
        end
        ::continue::
    end

    return deposit
end

---Checks if the table is an array with gaps in their indexes
---@param tab table
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
            return SaveManager.Utility.ValidityState.INVALID,
                SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE
        end

        if type(index) == "number" and math.floor(index) ~= index then
            return SaveManager.Utility.ValidityState.INVALID,
                SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE
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
    table.sort(callbacks, function(a, b)
        return a.Priority < b.Priority
    end)

    for _, callback in ipairs(callbacks) do
        callback.Function(callback.Mod, ...)
    end
end

---@alias DataDuration "run" | "floor" | "roomFloor" | "room"

---Checks if the entity type with the given save data's duration is permitted within the save manager.
---@param entType integer | Vector
---@param dataDuration DataDuration
function SaveManager.Utility.IsDataTypeAllowed(entType, dataDuration)
    if type(entType) == "number"
        and entType ~= EntityType.ENTITY_PLAYER
        and entType ~= EntityType.ENTITY_FAMILIAR
        and entType ~= EntityType.ENTITY_PICKUP
        and entType ~= EntityType.ENTITY_SLOT
    then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.INVALID_ENTITY_TYPE)
        return false
    end
    if (type(entType) == "userdata" --Vector for grid ents
            or type(entType) == "number"
            and (entType == EntityType.ENTITY_SLOT
                or entType == EntityType.ENTITY_PICKUP))
        and (dataDuration == "run"
            or dataDuration == "floor"
        )
    then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.INVALID_TYPE_WITH_SAVE)
        return false
    end
    return true
end

function SaveManager.Utility.IsDataInitialized()
    if not modReference then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
        return false
    end

    if not loadedData then
        SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
        return false
    end

    return true
end

--[[
    ################################
    #  DEFAULT DATA METHODS START  #
    ################################
]]

---@param saveKey string
---@param dataDuration DataDuration
---@param data table
local function addDefaultData(saveKey, dataDuration, data)
    if not SaveManager.Utility.IsConstructSaveKey(saveKey)
        and not not SaveManager.Utility.IsDefaultSaveKey(saveKey) then
        return
    end
    saveKey = saveKey:gsub("DEFAULT", "CONSTRUCT")
    local keyToType = {
        [SaveManager.ConstructSaveKeys.PLAYER] = EntityType.ENTITY_PLAYER,
        [SaveManager.ConstructSaveKeys.FAMILIAR] = EntityType.ENTITY_FAMILIAR,
        [SaveManager.ConstructSaveKeys.PICKUP] = EntityType.ENTITY_PICKUP,
        [SaveManager.ConstructSaveKeys.SLOT] = EntityType.ENTITY_SLOT
    }
    if saveKey ~= SaveManager.ConstructSaveKeys.GLOBAL
        and not SaveManager.Utility.IsDataTypeAllowed(keyToType[saveKey], dataDuration)
    then
        return
    end
    local dataTable = SaveManager.DEFAULT_SAVE_CONSTRUCTOR[dataDuration]

    ---@cast saveKey string
    if dataTable[saveKey] == nil then
        dataTable[saveKey] = {}
    end
    dataTable = dataTable[saveKey]

    SaveManager.Utility.SendDebugMessage(saveKey, dataDuration)
    SaveManager.Utility.PatchSaveFile(dataTable, data)
end

---Adds data that will be automatically added when the run data is first initialized.
---@param dataType DefaultSaveKeys
---@param data table
function SaveManager.Utility.AddDefaultRunData(dataType, data)
    addDefaultData(dataType, "run", data)
end

---Adds data that will be automatically added when the floor data is first initialized.
---@param dataType DefaultSaveKeys
---@param data table
function SaveManager.Utility.AddDefaultFloorData(dataType, data)
    addDefaultData(dataType, "floor", data)
end

---Adds data that will be automatically added when the room data is first initialized.
---@param dataType DefaultSaveKeys
---@param data table
function SaveManager.Utility.AddDefaultRoomData(dataType, data)
    addDefaultData(dataType, "room", data)
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
    if not SaveManager.Utility.IsDataInitialized() then return end

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
        local newData = SaveManager.Utility.DeepCopy(hourglassBackup)
        dataCache.game = SaveManager.Utility.PatchSaveFile(newData, SaveManager.DEFAULT_SAVE.game)
        skipRoomReset = true
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
    #  PICKUP METHODS START  #
    ##########################
]]

---@param lastIndex? boolean
local function getListIndex(lastIndex)
    return tostring(lastIndex and game:GetLevel():GetLastRoomDesc().ListIndex or
    game:GetLevel():GetCurrentRoomDesc().ListIndex)
end

---@param pickup EntityPickup
---@param lastIndex? boolean
---@return table?
local function getRoomFloorPickupData(pickup, lastIndex)
    local listIndexData = dataCache.game.roomFloor[getListIndex(lastIndex)]
    if not listIndexData then
        return
    end
    SaveManager.Utility.SendDebugMessage("get pickup data for index", getListIndex(lastIndex))
    return listIndexData[SaveManager.Utility.GetSaveIndex(pickup)]
end

---Gets a unique string as an identifier for the pickup when outside of the room it's present in.
---@param pickup EntityPickup
---@param lastIndex? boolean
function SaveManager.Utility.GetPickupIndex(pickup, lastIndex)
    local level = game:GetLevel()
    local index = table.concat(
        { "PICKUP_FLOORDATA",
            getListIndex(lastIndex),
            math.floor(pickup.Position.X),
            math.floor(pickup.Position.Y),
            pickup.InitSeed },
        "_")
    if myosotisCheck then
        --Trick code to pulling previous floor's data only if initseed matches.
        --Even with dupe initseeds pickups spawning, it'll go through and init data for each one

        for myosotisIndex, _ in pairs(dataCache.game.pickup.floor) do
            local initSeed = pickup.InitSeed
            if string.sub(myosotisIndex, -string.len(tostring(initSeed)), -1) == tostring(initSeed) then
                index = myosotisIndex
                SaveManager.Utility.SendDebugMessage("Myotosis data found for")
                break
            end
        end
    end
    return index
end

---Gets run-persistent pickup data if it was inside a boss room.
---@param pickup EntityPickup
---@return table?
function SaveManager.Utility.GetPickupAscentBoss(pickup)
    local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
    local pickupData = dataCache.game.pickup.bossRoom[pickupIndex]
    return pickupData
end

---Gets run-persistent pickup data if it was inside a treasure room.
---@param pickup EntityPickup
---@return table?
function SaveManager.Utility.GetPickupAscentTreasure(pickup)
    local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
    local pickupData = dataCache.game.pickup.treasureRoom[pickupIndex]
    return pickupData
end

---Gets the pickup's persistent data for the floor to keep track of it outside rooms.
---Also checks if was stored inside the boss or treasure room save data used for the Ascent.
---
---You won't use this yourself as the pickup's persistent data is immediately nulled once the pickup in the room is loaded in. Use `GetFloorSave` instead.
---@param pickup EntityPickup
---@return table?, string
function SaveManager.Utility.GetPickupData(pickup)
    local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
    local pickupData = dataCache.game.pickup.floor[pickupIndex]
    if not pickupData and game:GetLevel():IsAscent() then
        SaveManager.Utility.SendDebugMessage("Was unable to locate floor-saved room data. Searching Ascent...")
        if game:GetRoom():GetType() == RoomType.ROOM_BOSS then
            pickupData = SaveManager.Utility.GetPickupAscentBoss(pickup)
        elseif game:GetRoom():GetType() == RoomType.ROOM_TREASURE then
            pickupData = SaveManager.Utility.GetPickupAscentTreasure(pickup)
        end
    end
    return pickupData, pickupIndex
end

---When leaving the room, stores floor-persistent pickup data.
---@param pickup EntityPickup
local function storePickupData(pickup)
    local roomPickupData = getRoomFloorPickupData(pickup, not storePickupDataOnGameExit)
    if not roomPickupData then
        SaveManager.Utility.SendDebugMessage("Failed to find room data for", SaveManager.Utility.GetSaveIndex(pickup))
        return
    end
    local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup, not storePickupDataOnGameExit)
    local pickupData = dataCache.game.pickup
    if game:GetRoom():GetType() == RoomType.ROOM_TREASURE then
        pickupData.treasureRoom[pickupIndex] = roomPickupData
    elseif game:GetRoom():GetType() == RoomType.ROOM_BOSS then
        pickupData.bossRoom[pickupIndex] = roomPickupData
    end
    pickupData.floor[pickupIndex] = roomPickupData
    SaveManager.Utility.SendDebugMessage("Stored pickup data for", pickupIndex, pickupData.floor[pickupIndex])
end

---When re-entering a room, gives back floor-persistent data to valid pickups.
---@param pickup EntityPickup
local function populatePickupData(pickup)
    local pickupData = SaveManager.Utility.GetPickupData(pickup)
    if pickupData then
        dataCache.game.roomFloor[getListIndex()][SaveManager.Utility.GetSaveIndex(pickup)] = pickupData
        SaveManager.Utility.SendDebugMessage("Successfully populated pickup data from floor-saved room data for",
            SaveManager.Utility.GetSaveIndex(pickup))
        local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
        if game:GetRoom():GetType() == RoomType.ROOM_BOSS then
            dataCache.game.pickup.bossRoom[pickupIndex] = nil
        elseif game:GetRoom():GetType() == RoomType.ROOM_TREASURE then
            dataCache.game.pickup.treasureRoom[pickupIndex] = nil
        end
        dataCache.game.pickup.floor[pickupIndex] = nil
    else
        SaveManager.Utility.SendDebugMessage("Failed to find floor-saved room data for",
            SaveManager.Utility.GetPickupIndex(pickup))
    end
end

--[[
    ##########################
    #  CORE CALLBACKS START  #
    ##########################
]]

local function onGameLoad()
    storePickupDataOnGameExit = false
    ---@param target table
    local function constructDefaultSave(target)
        for dataDuration, dataTable in pairs(SaveManager.DEFAULT_SAVE_CONSTRUCTOR) do
            local targetTab = target[dataDuration]
            for saveKey, keyTable in pairs(dataTable) do
                if saveKey == SaveManager.DefaultSaveKeys.CONSTRUCT_GLOBAL then
                    targetTab[SaveManager.DefaultSaveKeys.GLOBAL] = SaveManager.Utility.DeepCopy(keyTable)
                else
                    local defaultSaveKey = string.gsub(saveKey, "CONSTRUCT", "DEFAULT")
                    targetTab[defaultSaveKey] = SaveManager.Utility.DeepCopy(keyTable)
                    SaveManager.Utility.SendDebugMessage("Created default", dataDuration, "data for",
                        defaultSaveKey)
                end
            end
        end
    end
    constructDefaultSave(SaveManager.DEFAULT_SAVE.game)
    constructDefaultSave(SaveManager.DEFAULT_SAVE.gameNoBackup)
    skipFloorReset = true
    skipRoomReset = true
    SaveManager.Load()
end

---@param ent? Entity
local function onEntityInit(_, ent)
    local newGame = game:GetFrameCount() == 0 and not ent
    local saveIndex = SaveManager.Utility.GetSaveIndex(ent)

    if not loadedData then
        SaveManager.Utility.SendDebugMessage("Game Init")
        onGameLoad()
        loadedData = true
    end
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

    -- go through the default save, look for appropriate default keys, and copy those in the same spot in the target save
    local function implementSaveKeys(tab, target, history)
        history = history or {}
        for i, v in pairs(tab) do
            if i == SaveManager.Utility.GetDefaultSaveKey(ent) then
                local targetTable = reconstructHistory(target, history)
                if targetTable and not targetTable[saveIndex] then
                    SaveManager.Utility.SendDebugMessage("Attempting default data transfer")
                    -- create or patch the target table with the default save
                    local newData = SaveManager.Utility.PatchSaveFile(targetTable[saveIndex] or {}, v)
                    -- Only creates data if it was filled with default data
                    if next(newData) ~= nil then
                        targetTable[saveIndex] = newData
                        SaveManager.Utility.SendDebugMessage("Default data copied for", saveIndex)
                    else
                        SaveManager.Utility.SendDebugMessage("No default data found for", saveIndex)
                    end
                    targetTable[i] = nil
                else
                    SaveManager.Utility.SendDebugMessage("Was unable to fetch target table/data is already loaded for",
                        saveIndex)
                end
            elseif type(v) == "table" then
                table.insert(history, i)
                implementSaveKeys(v, target, history)
                table.remove(history)
            end
        end
        return target
    end
    if ent and ent.Type == EntityType.ENTITY_PICKUP then
        local pickup = ent:ToPickup()
        ---@cast pickup EntityPickup
        populatePickupData(pickup)
        if getRoomFloorPickupData(pickup) then
            return --Don't populate default data if it has previous room data already!
        end
    end
    implementSaveKeys(SaveManager.DEFAULT_SAVE.game, dataCache.game)
    implementSaveKeys(SaveManager.DEFAULT_SAVE.gameNoBackup, dataCache.gameNoBackup)
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

---@param type "floor" | "roomFloor" | "room"
local function resetData(type)
    if (not skipRoomReset and type == "room") or (not skipFloorReset and (type == "roomFloor" or type == "floor")) then
        if not hourglassBackup then hourglassBackup = {} end
        hourglassBackup.run = SaveManager.Utility.DeepCopy(dataCache.game.run)
        hourglassBackup[type] = SaveManager.Utility.DeepCopy(dataCache.game[type])
        if type == "floor" then
            hourglassBackup.pickup.floor = SaveManager.Utility.DeepCopy(dataCache.game.pickup.floor)
            if not myosotisCheck then
                dataCache.game.pickup.floor = {}
            end
        end
        dataCache.game[type] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game[type])
        dataCache.gameNoBackup[type] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup[type])
        SaveManager.Save()
        SaveManager.Utility.SendDebugMessage("reset", type, "data")
        shouldRestoreOnUse = true
    end
    if type == "room" then
        skipRoomReset = false
    elseif type == "floor" then
        skipFloorReset = false
    end
end

local function preGameExit()
    SaveManager.Utility.SendDebugMessage("pre game exit")
    storePickupDataOnGameExit = true
    for _, pickup in pairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
        ---@cast pickup EntityPickup
        storePickupData(pickup)
    end
    SaveManager.Save()
    loadedData = false
    inRunButNotLoaded = false
    shouldRestoreOnUse = false
end

---@param ent Entity
local function postEntityRemove(_, ent)
    if not dataCache.game
        or (ent.Type ~= EntityType.ENTITY_PLAYER
            and ent.Type ~= EntityType.ENTITY_FAMILIAR
            and ent.Type ~= EntityType.ENTITY_PICKUP
            and ent.Type ~= EntityType.ENTITY_SLOT
        )
    then
        return
    end

    if game:IsPaused() and not storePickupDataOnGameExit then
        if ent:ToPickup() then
            ---@cast ent EntityPickup
            storePickupData(ent)
        end
        return
    end
    local saveIndex = SaveManager.Utility.GetSaveIndex(ent)

    ---@param tab GameSave
    local function removeSaveData(tab)
        for dataDuration, dataTable in pairs(tab) do
            if dataDuration == "roomFloor" and dataTable[getListIndex()] then
                removeSaveData(dataTable)
            elseif dataTable[saveIndex] then
                SaveManager.Utility.SendDebugMessage("Removed data", saveIndex)
                dataTable[saveIndex] = nil
            end
        end
    end
    removeSaveData(dataCache.game)
    removeSaveData(dataCache.gameNoBackup)
end

--A safety precaution to make sure data for entities that no longer exist are removed from room data.
local function removeLeftoverEntityData()
    SaveManager.Utility.SendDebugMessage("leftover ent data check")
    local function removeLeftoverData(tab)
        for key, _ in pairs(tab) do
            local separation = string.find(key, "_") --Will stop global-type data and pickup data from being checked
            if not separation then goto continue end
            local entName = string.sub(key, 1, separation - 1)
            local nameToType = {
                ["PLAYER"] = EntityType.ENTITY_PLAYER,
                ["FAMILIAR"] = EntityType.ENTITY_FAMILIAR,
                ["PICKUP"] = EntityType.ENTITY_PICKUP,
                ["SLOT"] = EntityType.ENTITY_SLOT,
            }
            local entType = nameToType[entName]
            SaveManager.Utility.SendDebugMessage("Searching for leftover data under", entType)
            if entType then
                for _, ent in pairs(Isaac.FindByType(entType)) do
                    local index = SaveManager.Utility.GetSaveIndex(ent)
                    if key == index then goto continue end --Found entity, no need to remove
                end
            end
            SaveManager.Utility.SendDebugMessage("Leftover data removed for", key)
            tab[key] = nil
            ::continue::
        end
    end
    removeLeftoverData(dataCache.game.room)
    removeLeftoverData(dataCache.gameNoBackup.room)
end

local function postNewRoom()
    SaveManager.Utility.SendDebugMessage("new room")
    resetData("room")
    removeLeftoverEntityData()
end

local function postNewLevel()
    SaveManager.Utility.SendDebugMessage("new level")
    resetData("roomFloor")
    resetData("floor")
    for i = 0, game:GetNumPlayers() - 1 do
        if Isaac.GetPlayer(i):HasTrinket(TrinketType.TRINKET_MYOSOTIS) then
            myosotisCheck = true
            break
        end
    end
end

local function postUpdate()
    if myosotisCheck then --Triggers after entities finish spawning on new floor
        dataCache.game.pickup.floor = {}
        myosotisCheck = false
    end
    if not REPENTOGON then return end
    for _, slot in pairs(Isaac.FindByType(EntityType.ENTITY_SLOT)) do
        if slot.FrameCount == 0 then
            onEntityInit(_, slot)
        end
    end
end

--[[
    ##########################
    #  INITIALIZATION LOGIC  #
    ##########################
]]

-- Initializes the save manager.
---@param mod table @The reference to your mod. This is the table that is returned when you call `RegisterMod`.
function SaveManager.Init(mod, j)
    modReference = mod
    json = j

    modReference:AddCallback(ModCallbacks.MC_USE_ITEM, SaveManager.HourglassRestore,
        CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
    -- it runs before the game started callback lol
    modReference:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function() onEntityInit() end) --Global data
    modReference:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, onEntityInit)
    modReference:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, onEntityInit)
    modReference:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, onEntityInit)
    modReference:AddCallback(ModCallbacks.MC_POST_SLOT_INIT, onEntityInit)
    modReference:AddPriorityCallback(ModCallbacks.MC_POST_PLAYER_RENDER, CallbackPriority.IMPORTANT, detectLuamod) -- want to run as early as possible
    modReference:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, postNewRoom)
    modReference:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, postNewLevel)
    modReference:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, preGameExit)
    modReference:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, postEntityRemove)
    modReference:AddCallback(ModCallbacks.MC_POST_UPDATE, postUpdate)
    if REPENTOGON then
        modReference:AddCallback(ModCallbacks.MC_POST_SLOT_INIT, onEntityInit)
    end

    -- used to detect if an unloaded mod is this mod for when saving for luamod
    modReference.__SAVEMANAGER_UNIQUE_KEY = ("%s-%s"):format(Random(), Random())
    modReference:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, modToUnload)
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

---@param ent? Entity | Vector
---@param noHourglass false|boolean?
---@param dataDuration DataDuration
---@param listIndex? integer
---@return table?
local function getRespectiveSave(ent, noHourglass, dataDuration, listIndex)
    if not SaveManager.Utility.IsDataInitialized()
        or (ent and not SaveManager.Utility.IsDataTypeAllowed(ent.Type, dataDuration))
    then
        return
    end
    noHourglass = noHourglass or false

    local saveIndex = SaveManager.Utility.GetSaveIndex(ent)
    local defaultKey = SaveManager.Utility.GetDefaultSaveKey(ent)
    local saveTableBackup = dataCache.game[dataDuration]
    local saveTableNoBackup = dataCache.gameNoBackup[dataDuration]
    local saveTable = noHourglass and saveTableNoBackup or saveTableBackup

    if not saveTable then return saveTable end
    local stringIndex = tostring(listIndex or getListIndex())
    if dataDuration == "roomFloor" then
        if not saveTable[stringIndex] then
            SaveManager.Utility.SendDebugMessage("Created index", stringIndex)
            saveTable[stringIndex] = {}
        end
        saveTable = saveTable[stringIndex]
    end
    local data = saveTable[saveIndex]

    if data == nil then
        local defaultSave = SaveManager.DEFAULT_SAVE[noHourglass and "gameNoBackup" or "game"][dataDuration]
            [defaultKey] or {}
        SaveManager.Utility.SendDebugMessage("Created new data for", saveIndex)
        saveTable[saveIndex] = SaveManager.Utility.PatchSaveFile({}, defaultSave)
    end

    return saveTable[saveIndex]
end

---@param ent? Entity | Vector @If an entity is provided, returns an entity specific save within the run save. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetRunSave(ent, noHourglass)
    return getRespectiveSave(ent, noHourglass, "run")
end

---@param ent? Entity | Vector  @If an entity is provided, returns an entity specific save within the floor save. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetFloorSave(ent, noHourglass)
    return getRespectiveSave(ent, noHourglass, "floor")
end

---@param ent? Entity | Vector @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetRoomFloorSave(ent, noHourglass, listIndex)
    return getRespectiveSave(ent, noHourglass, "roomFloor", listIndex)
end

---@param ent? Entity | Vector  @If an entity is provided, returns an entity specific save within the room save. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetRoomSave(ent, noHourglass)
    return getRespectiveSave(ent, noHourglass, "room")
end

---Returns uniquely-saved data for pickups when outside of the room they're stored in.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetPickupSave()
    if not SaveManager.Utility.IsDataInitialized() then return end

    return dataCache.game.pickup
end

---Please note that this is essentially a normal table with the connotation of being used with UnlockAPI.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetUnlockAPISave()
    if not SaveManager.Utility.IsDataInitialized() then return end

    return dataCache.file.unlockApi
end

---Please note that this is essentially a normal table with the connotation of being used with Dead Sea Scrolls (DSS).
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetDeadSeaScrollsSave()
    if not SaveManager.Utility.IsDataInitialized() then return end

    return dataCache.file.deadSeaScrolls
end

---Please note that this is essentially a normal table with the connotation of being used to store settings.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetSettingsSave()
    if not SaveManager.Utility.IsDataInitialized() then return end

    return dataCache.file.settings
end

---Gets the "type" save data within the file save. Basically just a table you can put anything it.
function SaveManager.GetPersistentSave()
    if not SaveManager.Utility.IsDataInitialized() then return end

    return dataCache.file.other
end

return SaveManager
