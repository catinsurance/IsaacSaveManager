---@diagnostic disable: missing-fields
-- Check out everything here: https://github.com/maya-bee/IsaacSaveManager

local game = Game()
local SaveManager = {}
SaveManager.VERSION = 2.12
SaveManager.Utility = {}

-- Used in the DEFAULT_SAVE table as a key with the value being the default save data for a player in this save type.

---@enum DefaultSaveKeys
SaveManager.DefaultSaveKeys = {
	PLAYER = "__DEFAULT_PLAYER",
	FAMILIAR = "__DEFAULT_FAMILIAR",
	PICKUP = "__DEFAULT_PICKUP",
	SLOT = "__DEFAULT_SLOT",
	GLOBAL = "__DEFAULT_GLOBAL",
}

local modReference
local json = require("json")
local loadedData = false
local skipFloorReset = false
local skipRoomReset = false
local shouldRestoreOnUse = true
local myosotisCheck = false
local movingBoxCheck = true
local currentFloor = 0
local currentListIndex = 0
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
	POST_DATA_SAVE = "ISAACSAVEMANAGER_POST_DATA_LOAD",
	PRE_DATA_LOAD = "ISAACSAVEMANAGER_PRE_DATA_LOAD",
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
---@field treasureRoom table @Things in this table are persistent for the entire run, meant for when you re-visit Treasure Room in the Ascent.
---@field bossRoom table @Things in this table are persistent for the entire run, meant for when you re-visit Boss Room in the Ascent.
---@field movingBox table Things in this table are persistent for the entire run, meant for storing pickups that are carried through Moving Box.

---@class FileSave
---@field unlockApi table @Built in compatibility for UnlockAPI (https://github.com/dsju/unlockapi)
---@field deadSeaScrolls table @Built in support for Dead Sea Scrolls (https://github.com/Meowlala/DeadSeaScrollsMenu)
---@field settings table @Miscellaneous table for anything settings-related.
---@field other table @Miscellaneous table for if you want to use your own unlock system or just need to store random data to the file.

---You can edit what is inside of these tables, but changing the overall structure of this table will break things.
---@class SaveData
SaveManager.DEFAULT_SAVE = {
	game = {
		run = {},
		floor = {},
		roomFloor = {},
		room = {},
		pickup = {
			floor = {},
			treasureRoom = {},
			bossRoom = {},
			movingBox = {}
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

--#region utility methods

SaveManager.Debug = false

function SaveManager.Utility.SendError(msg)
	local _, traceback = pcall(error, "", 5) -- 5 because it is 5 layers deep
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
		if getmetatable(ent).__type:find("Entity") then
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

--#endregion

--[[
    ################################
    #  DEFAULT DATA METHODS START  #
    ################################
]]

--#region default data

---@param saveKey string
---@param dataDuration DataDuration
---@param data table
---@param noHourglass? boolean
local function addDefaultData(saveKey, dataDuration, data, noHourglass)
	if not SaveManager.Utility.IsDefaultSaveKey(saveKey) then
		return
	end
	local keyToType = {
		[SaveManager.DefaultSaveKeys.PLAYER] = EntityType.ENTITY_PLAYER,
		[SaveManager.DefaultSaveKeys.FAMILIAR] = EntityType.ENTITY_FAMILIAR,
		[SaveManager.DefaultSaveKeys.PICKUP] = EntityType.ENTITY_PICKUP,
		[SaveManager.DefaultSaveKeys.SLOT] = EntityType.ENTITY_SLOT
	}
	if saveKey ~= SaveManager.DefaultSaveKeys.GLOBAL
		and not SaveManager.Utility.IsDataTypeAllowed(keyToType[saveKey], dataDuration)
	then
		return
	end

	local gameFile = noHourglass and SaveManager.DEFAULT_SAVE.gameNoBackup or SaveManager.DEFAULT_SAVE.game
	local dataTable = gameFile[dataDuration]

	---@cast saveKey string
	if dataTable[saveKey] == nil then
		dataTable[saveKey] = {}
	end
	dataTable = dataTable[saveKey]

	SaveManager.Utility.PatchSaveFile(dataTable, data)
	SaveManager.Utility.SendDebugMessage(saveKey, dataDuration)
end

---Adds data that will be automatically added when the run data is first initialized.
---@param dataType DefaultSaveKeys
---@param data table
---@param noHourglass? boolean @If true, will load data in a separate game save that is not affected by Glowing Hourglass.
function SaveManager.Utility.AddDefaultRunData(dataType, data, noHourglass)
	addDefaultData(dataType, "run", data, noHourglass)
end

---Adds data that will be automatically added when the floor data is first initialized.
---@param dataType DefaultSaveKeys
---@param data table
---@param noHourglass? boolean @If true, will load data in a separate game save that is not affected by Glowing Hourglass.
function SaveManager.Utility.AddDefaultFloorData(dataType, data, noHourglass)
	addDefaultData(dataType, "floor", data, noHourglass)
end

---Adds data that will be automatically added when the room data is first initialized.
---@param dataType DefaultSaveKeys
---@param data table
---@param noHourglass? boolean @If true, will load data in a separate game save that is not affected by Glowing Hourglass.
function SaveManager.Utility.AddDefaultRoomData(dataType, data, noHourglass)
	addDefaultData(dataType, "room", data, noHourglass)
end

--#endregion

--[[
    ########################
    #  CORE METHODS START  #
    ########################
]]

--#region core methods

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

	SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.POST_DATA_SAVE, finalData)
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
---@param isLuamod? boolean
function SaveManager.Load(isLuamod)
	if not modReference then
		SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
		return
	end

	local saveData = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE)

	if modReference:HasData() then
		local data = json.decode(modReference:LoadData())
		saveData = SaveManager.Utility.PatchSaveFile(data, SaveManager.DEFAULT_SAVE)
	end

	SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.PRE_DATA_LOAD, dataCache, isLuamod)

	dataCache = saveData
	hourglassBackup = SaveManager.Utility.DeepCopy(dataCache.hourglassBackup)

	loadedData = true
	inRunButNotLoaded = false

	SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.POST_DATA_LOAD, dataCache, isLuamod)
end

--[[
    ##########################
    #  PICKUP METHODS START  #
    ##########################
]]

---@param checkLastIndex? boolean
local function getListIndex(checkLastIndex)
	local level = game:GetLevel()
	if level:GetStage() ~= currentFloor then
		return tostring(currentListIndex)
	else
		return tostring(checkLastIndex and game:GetLevel():GetLastRoomDesc().ListIndex or
			game:GetLevel():GetCurrentRoomDesc().ListIndex)
	end
end

---@param pickup EntityPickup
---@param checkLastIndex? boolean
---@return table?
local function getRoomFloorPickupData(pickup, checkLastIndex)
	local listIndex = getListIndex(checkLastIndex)
	local listIndexData = dataCache.game.roomFloor[listIndex]

	if not listIndexData then
		return
	end
	return listIndexData[SaveManager.Utility.GetSaveIndex(pickup)]
end

---Gets a unique string as an identifier for the pickup when outside of the room it's present in.
---@param pickup EntityPickup
---@param checkLastIndex? boolean
function SaveManager.Utility.GetPickupIndex(pickup, checkLastIndex)
	local index = table.concat(
		{ "PICKUP_FLOORDATA",
			getListIndex(checkLastIndex),
			math.floor(pickup.Position.X),
			math.floor(pickup.Position.Y),
			pickup.InitSeed },
		"_")
	if myosotisCheck or movingBoxCheck then
		--Trick code to pulling previous floor's data only if initseed matches.
		--Even with dupe initseeds pickups spawning, it'll go through and init data for each one
		SaveManager.Utility.SendDebugMessage("Data active for a transferred pickup. Attempting to find data...")

		for backupIndex, _ in pairs(myosotisCheck and hourglassBackup.pickup.floor or dataCache.game.pickup.movingBox) do
			local initSeed = pickup.InitSeed

			if string.sub(backupIndex, -string.len(tostring(initSeed)), -1) == tostring(initSeed) then
				index = backupIndex
				SaveManager.Utility.SendDebugMessage("Stored data found for",
					SaveManager.Utility.GetSaveIndex(pickup) .. ".")
				break
			end
		end
	end
	return index
end

local function getStoredPickupData(dataStorage, pickupIndex)
	if myosotisCheck then
		return hourglassBackup.pickup[dataStorage][pickupIndex]
	elseif movingBoxCheck then
		return dataCache.game.pickup.movingBox[pickupIndex]
	else
		return dataCache.game.pickup[dataStorage][pickupIndex]
	end
end

---Gets run-persistent pickup data if it was inside a boss room.
---@param pickup EntityPickup
---@return table?
function SaveManager.Utility.GetPickupAscentBoss(pickup)
	local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
	local pickupData = getStoredPickupData("bossRoom", pickupIndex)
	return pickupData
end

---Gets run-persistent pickup data if it was inside a treasure room.
---@param pickup EntityPickup
---@return table?
function SaveManager.Utility.GetPickupAscentTreasure(pickup)
	local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
	local pickupData = getStoredPickupData("treasureRoom", pickupIndex)
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
	local pickupData = getStoredPickupData("floor", pickupIndex)
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
	if movingBoxCheck then
		pickupData.movingBox[pickupIndex] = roomPickupData
		SaveManager.Utility.SendDebugMessage("Stored Moving Box pickup data for", pickupIndex)
	else
		if game:GetRoom():GetType() == RoomType.ROOM_TREASURE then
			pickupData.treasureRoom[pickupIndex] = roomPickupData
		elseif game:GetRoom():GetType() == RoomType.ROOM_BOSS then
			pickupData.bossRoom[pickupIndex] = roomPickupData
		end
		pickupData.floor[pickupIndex] = roomPickupData
		SaveManager.Utility.SendDebugMessage("Stored pickup data for", pickupIndex)
	end
end

---When re-entering a room, gives back floor-persistent data to valid pickups.
---@param pickup EntityPickup
local function populatePickupData(pickup)
	local pickupData = SaveManager.Utility.GetPickupData(pickup)
	if pickupData then
		if dataCache.game.roomFloor[getListIndex()] == nil then
			dataCache.game.roomFloor[getListIndex()] = {}
		end
		dataCache.game.roomFloor[getListIndex()][SaveManager.Utility.GetSaveIndex(pickup)] = pickupData
		SaveManager.Utility.SendDebugMessage("Successfully populated pickup data from floor-saved room data for",
			SaveManager.Utility.GetSaveIndex(pickup))
		local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
		if movingBoxCheck then
			dataCache.game.pickup.movingBox[pickupIndex] = nil
		else
			if game:GetRoom():GetType() == RoomType.ROOM_BOSS then
				dataCache.game.pickup.bossRoom[pickupIndex] = nil
			elseif game:GetRoom():GetType() == RoomType.ROOM_TREASURE then
				dataCache.game.pickup.treasureRoom[pickupIndex] = nil
			end
			dataCache.game.pickup.floor[pickupIndex] = nil
		end
	else
		SaveManager.Utility.SendDebugMessage("Failed to find floor-saved room data for",
			SaveManager.Utility.GetPickupIndex(pickup))
	end
end

--#endregion

--[[
    ##########################
    #  CORE CALLBACKS START  #
    ##########################
]]

--#region core callbacks

local function onGameLoad()
	storePickupDataOnGameExit = false
	skipFloorReset = true
	skipRoomReset = true
	SaveManager.Load(false)
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
					local newData
					if i == SaveManager.DefaultSaveKeys.PICKUP and ent then
						local pickupData = {
							InitSeed = ent.InitSeed,
							RerollSave = SaveManager.Utility.PatchSaveFile(
								targetTable.RerollSave and targetTable.RerollSave[saveIndex] or {}, v),
							NoRerollSave = SaveManager.Utility.PatchSaveFile(
								targetTable.NoRerollSave and targetTable.NoRerollSave[saveIndex] or {}, v)
						}
						target[saveIndex] = pickupData
						newData = pickupData
					else
						newData = SaveManager.Utility.PatchSaveFile(targetTable[saveIndex] or {}, v)
					end
					-- Only creates data if it was filled with default data
					if next(newData) ~= nil then
						targetTable[saveIndex] = newData
						SaveManager.Utility.SendDebugMessage("Default data copied for", saveIndex)
					else
						SaveManager.Utility.SendDebugMessage("No default data found for", saveIndex)
					end
					targetTable[i] = nil
				else
					SaveManager.Utility.SendDebugMessage(
						"Was unable to fetch target table or data is already loaded for",
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
	if (REPENTOGON or game:GetFrameCount() > 0)
		and not loadedData and inRunButNotLoaded
	then
		SaveManager.Load(true)
		inRunButNotLoaded = false
		shouldRestoreOnUse = true
		if game:GetFrameCount() > 0 then
			currentListIndex = game:GetLevel():GetCurrentRoomDesc().ListIndex
			currentFloor = game:GetLevel():GetStage()
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
			SaveManager.Save()
		elseif type == "room" then
			--roomFloor data from gotoCommands should be removed, as if it were a room save. It is not persistent.
			if dataCache.game.roomFloor["509"] then
				dataCache.game.roomFloor["509"] = nil
			end
			if dataCache.gameNoBackup.roomFloor["509"] then
				dataCache.gameNoBackup.roomFloor["509"] = nil
			end
		end
		dataCache.game[type] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game[type])
		dataCache.gameNoBackup[type] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup[type])
		SaveManager.Utility.SendDebugMessage("reset", type, "data")
		shouldRestoreOnUse = true
	end
	if type == "room" then
		skipRoomReset = false
	elseif type == "floor" then
		skipFloorReset = false
	end
end

local function preGameExit(_, shouldSave)
	SaveManager.Utility.SendDebugMessage("pre game exit")
	if shouldSave then
		storePickupDataOnGameExit = true
		for _, pickup in pairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
			---@cast pickup EntityPickup
			storePickupData(pickup)
		end
	else
		dataCache.game = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		dataCache.gameNoBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup)
		hourglassBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
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

	if (game:IsPaused() and not storePickupDataOnGameExit) or (ent.Type == EntityType.ENTITY_PICKUP and movingBoxCheck) then
		if ent.Type == EntityType.ENTITY_PICKUP then
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
	currentListIndex = game:GetLevel():GetCurrentRoomDesc().ListIndex
	resetData("room")
	removeLeftoverEntityData()
end

local function postNewLevel()
	SaveManager.Utility.SendDebugMessage("new level")
	currentFloor = game:GetLevel():GetStage()
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
	myosotisCheck = false
	movingBoxCheck = false
end

local function postSlotInitNoRGON()
	for _, slot in pairs(Isaac.FindByType(EntityType.ENTITY_SLOT)) do
		if slot.FrameCount <= 1 then
			onEntityInit(_, slot)
		end
	end
end

---@param pickup EntityPickup
local function postPickupUpdate(_, pickup)
	local function resetNoRerollData(tab, default)
		for i = 1, 2 do
			local dataLength = i == 1 and "roomFloor" or "room"
			local saveIndex = SaveManager.Utility.GetSaveIndex(pickup)
			local data = tab[dataLength][saveIndex]
			if not data then goto continue end
			if data.InitSeed ~= pickup.InitSeed then
				data.NoRerollSave = SaveManager.Utility.PatchSaveFile({}, default[dataLength])
				data.InitSeed = pickup.InitSeed
				SaveManager.Utility.SendDebugMessage("Detected init seed change in", saveIndex,
					"! RerollSave has been reloaded")
			end
			::continue::
		end
	end
	resetNoRerollData(dataCache.game, SaveManager.DEFAULT_SAVE.game)
	resetNoRerollData(dataCache.gameNoBackup, SaveManager.DEFAULT_SAVE.gameNoBackup)
end

---With REPENTOGON, allows you to load data whenever you select a save slot.
---@param saveSlot integer
---@param isSlotSelected boolean
---@param rawSlot integer
local function postSaveSlotLoad(saveSlot, isSlotSelected, rawSlot)
	if not isSlotSelected then
		return
	end
	SaveManager.Load(false)
end

--#endregion

--[[
    ##########################
    #  INITIALIZATION LOGIC  #
    ##########################
]]

--#region init logic

-- Initializes the save manager.
---@param mod table @The reference to your mod. This is the table that is returned when you call `RegisterMod`.
function SaveManager.Init(mod)
	modReference = mod
	modReference:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, CallbackPriority.EARLY, SaveManager.HourglassRestore,
		CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
	-- Priority callbacks put in place to load data early and save data late.

	--Global data
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_PLAYER_INIT, CallbackPriority.IMPORTANT,
		function() onEntityInit() end)

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_PLAYER_INIT, CallbackPriority.IMPORTANT, onEntityInit)
	modReference:AddPriorityCallback(ModCallbacks.MC_FAMILIAR_INIT, CallbackPriority.IMPORTANT, onEntityInit)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_PICKUP_INIT, CallbackPriority.IMPORTANT, onEntityInit)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.EARLY, postUpdate)
	if REPENTOGON then
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_SLOT_INIT, CallbackPriority.IMPORTANT, onEntityInit)
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, CallbackPriority.IMPORTANT, postSaveSlotLoad)
		modReference:AddPriorityCallback(ModCallbacks.MC_MENU_INPUT_ACTION, CallbackPriority.IMPORTANT, detectLuamod)
	else
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.IMPORTANT, postSlotInitNoRGON)
	end

	--load luamod as early as possible.
	modReference:AddPriorityCallback(ModCallbacks.MC_INPUT_ACTION, CallbackPriority.IMPORTANT, detectLuamod)

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, CallbackPriority.EARLY, postNewRoom)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_NEW_LEVEL, CallbackPriority.EARLY, postNewLevel)
	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, CallbackPriority.LATE, preGameExit)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, CallbackPriority.LATE, postEntityRemove)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, CallbackPriority.EARLY, postPickupUpdate)
	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_USE_ITEM, CallbackPriority.LATE,
		function() movingBoxCheck = true end,
		CollectibleType.COLLECTIBLE_MOVING_BOX)
	modReference:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, CallbackPriority.EARLY,
		function() movingBoxCheck = false end,
		CollectibleType.COLLECTIBLE_MOVING_BOX)

	-- used to detect if an unloaded mod is this mod for when saving for luamod
	modReference.__SAVEMANAGER_UNIQUE_KEY = ("%s-%s"):format(Random(), Random())
	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, CallbackPriority.EARLY, function(_, modToUnload)
		if modToUnload.__SAVEMANAGER_UNIQUE_KEY and modToUnload.__SAVEMANAGER_UNIQUE_KEY == modReference.__SAVEMANAGER_UNIQUE_KEY then
			if loadedData then
				SaveManager.Save()
			end
		end
	end)
end

--#endregion

--[[
    ########################
    #  SAVE METHODS START  #
    ########################
]]

--#region save methods

-- Returns the entire save table, including the file save.
function SaveManager.GetEntireSave()
	return dataCache
end

---@param ent? Entity | Vector
---@param noHourglass false|boolean?
---@param initDataIfNotPresent? boolean
---@param dataDuration DataDuration
---@param listIndex? integer
---@return table
local function getRespectiveSave(ent, noHourglass, initDataIfNotPresent, dataDuration, listIndex)
	if not SaveManager.Utility.IsDataInitialized()
		or (ent and not SaveManager.Utility.IsDataTypeAllowed(ent.Type, dataDuration))
	then
		---@diagnostic disable-next-line: missing-return-value
		return
	end
	noHourglass = noHourglass or false

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
	local saveIndex = SaveManager.Utility.GetSaveIndex(ent)
	local data = saveTable[saveIndex]

	if data == nil and initDataIfNotPresent then
		local gameSave = noHourglass and "gameNoBackup" or "game"
		local defaultKey = SaveManager.Utility.GetDefaultSaveKey(ent)
		local defaultSave = SaveManager.DEFAULT_SAVE[gameSave][dataDuration][defaultKey] or {}
		if ent and getmetatable(ent).__type ~= "Vector" and ent.Type == EntityType.ENTITY_PICKUP then
			local pickupData = {
				InitSeed = ent.InitSeed,
				RerollSave = SaveManager.Utility.PatchSaveFile({}, defaultSave),
				NoRerollSave = SaveManager.Utility.PatchSaveFile({}, defaultSave)
			}
			saveTable[saveIndex] = pickupData
		else
			saveTable[saveIndex] = SaveManager.Utility.PatchSaveFile({}, defaultSave)
		end
		SaveManager.Utility.SendDebugMessage("Created new data for", saveIndex)
	end

	return saveTable[saveIndex]
end

---@param ent? Entity @If an entity is provided, returns an entity specific save within the run save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRunSave(ent, noHourglass)
	return getRespectiveSave(ent, noHourglass, true, "run")
end

---@param ent? Entity @If an entity is provided, returns an entity specific save within the run save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRunSave(ent, noHourglass)
	return getRespectiveSave(ent, noHourglass, false, "run")
end

---@param ent? Entity  @If an entity is provided, returns an entity specific save within the floor save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetFloorSave(ent, noHourglass)
	return getRespectiveSave(ent, noHourglass, true, "floor")
end

---**NOTE:** If your data is a pickup, it will return a table of {InitSeed: integer, RerollSave: table, NoRerollSave: table}. Please access your data from the Reroll or NoRerollSave. You can create a wrapper of calling either if you wish!
---@param ent? Entity  @If an entity is provided, returns an entity specific save within the floor save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetFloorSave(ent, noHourglass)
	return getRespectiveSave(ent, noHourglass, false, "floor")
end

---**NOTE:** If your data is a pickup, it will return a table of {InitSeed: integer, RerollSave: table, NoRerollSave: table}. Please access your data from the Reroll or NoRerollSave. You can create a wrapper of calling either if you wish!
---@param ent? Entity | Vector @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRoomFloorSave(ent, noHourglass, listIndex)
	return getRespectiveSave(ent, noHourglass, true, "roomFloor", listIndex)
end

---@param ent? Entity | Vector @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRoomFloorSave(ent, noHourglass, listIndex)
	return getRespectiveSave(ent, noHourglass, false, "roomFloor", listIndex)
end

---@param ent? Entity | Vector  @If an entity is provided, returns an entity specific save within the room save. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRoomSave(ent, noHourglass)
	return getRespectiveSave(ent, noHourglass, true, "room")
end

---@param ent? Entity | Vector  @If an entity is provided, returns an entity specific save within the room save. If a Vector is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass false|boolean? @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRoomSave(ent, noHourglass)
	return getRespectiveSave(ent, noHourglass, false, "room")
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

--#endregion

return SaveManager
