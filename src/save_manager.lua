---@diagnostic disable: missing-fields
-- Check out everything here: https://github.com/catinsurance/IsaacSaveManager/

local game = Game()
local SaveManager = {}
SaveManager.VERSION = 2.2
SaveManager.Utility = {}

SaveManager.Debug = false

SaveManager.AutoCreateRoomSaves = true

local mFloor = math.floor

-- Used in the DEFAULT_SAVE table as a key with the value being the default save data for a player in this save type.

---@enum DefaultSaveKeys
SaveManager.DefaultSaveKeys = {
	PLAYER = "__DEFAULT_PLAYER",
	FAMILIAR = "__DEFAULT_FAMILIAR",
	PICKUP = "__DEFAULT_PICKUP",
	SLOT = "__DEFAULT_SLOT",
	BOMB = "__DEFAULT_BOMB",
	GLOBAL = "__DEFAULT_GLOBAL",
}

local modReference
local minimapAPIReference
local json = require("json")
local loadedData = false
local dontSaveModData = true
local skipFloorReset = false
local skipRoomReset = false
local shouldRestoreOnUse = true
local usedHourglass = false
local myosotisCheck = false
local movingBoxCheck = false
local currentListIndex = 0
local checkLastIndex = false
local inRunButNotLoaded = true
local dupeTaggedPickups = {}
local allowedAscentRooms = {}

---@class SaveData
local dataCache = {}
---@class GameSave
local hourglassBackup = {}

SaveManager.Utility.ERROR_MESSAGE_FORMAT = "[IsaacSaveManager:%s] ERROR: %s (%s)\n"
SaveManager.Utility.WARNING_MESSAGE_FORMAT = "[IsaacSaveManager:%s] WARNING: %s (%s)\n"
SaveManager.Utility.ErrorMessages = {
	NOT_INITIALIZED = "The save manager cannot be used without initializing it first!",
	DATA_NOT_LOADED = "An attempt to use save data was made before it was loaded!",
	BAD_DATA = "An attempt to save invalid data was made!",
	BAD_DATA_WARNING = "Data type saved with warning!",
	COPY_ERROR =
	"An error was made when copying from cached data to what would be saved! This could be due to a circular reference.",
	INVALID_ENTITY_TYPE = "Error using entity type \"%s\": The save manager cannot support non-persistent entities!",
	INVALID_TYPE_WITH_SAVE =
	"An error was made using entity type \"%s\": This entity type does not support this save data as it does not persist between floors or move between rooms."
}
SaveManager.Utility.JsonIncompatibilityType = {
	SPARSE_ARRAY = "Sparse arrays, or arrays with gaps between indexes, will fill gaps with null when encoded.",
	INVALID_KEY_TYPE = "Error at index \"%s\" with value \"%s\", type \"%s\": Tables that have non-string or non-integer (decimal or non-number) keys cannot be encoded.",
	MIXED_TABLES = "Index \"%s\" with value \"%s\", type \"%s\", found in table with initial type \"%s\": Tables with mixed key types cannot be encoded.",
	NAN_VALUE = "Tables with invalid numbers (NaN, -inf, inf) cannot be encoded.",
	INVALID_VALUE = "Error at index \"%s\" with value \"%s\", type \"%s\": Tables containing anything other than strings, numbers, booleans, or other tables cannot be encoded.",
	CIRCULAR_TABLE = "Tables that contain themselves cannot be encoded.",
}

---@enum SaveCallbacks
SaveManager.SaveCallbacks = {
	---(SaveData saveData): SaveData - Called before validating the save data to store into the mod's save file. This will not run if there happens to be an issue with copying the contents of the save data or its hourglass backup. Modify the existing contents of the table or return a new table to overwrite the provided save data. As this is a copy, it will not affect the save data currently accessible
	PRE_DATA_SAVE = "ISAACSAVEMANAGER_PRE_DATA_SAVE",
	---(SaveData saveData) - Called after storing save data into the mod's save file
	POST_DATA_SAVE = "ISAACSAVEMANAGER_POST_DATA_SAVE",
	---(SaveData saveData, boolean isLuamod): SaveData - Called after loading the data from the mod's save file but before loading it into the local save data. Modify the existing contents of the table or return a new table to overwrite the provided save data. `isLuamod` will return `true` if the mod's data was reloaded via the luamod command
	PRE_DATA_LOAD = "ISAACSAVEMANAGER_PRE_DATA_LOAD",
	---(SaveData saveData, boolean isLuamod) - Called after loading the mod's save file and storing it in local save data
	POST_DATA_LOAD = "ISAACSAVEMANAGER_POST_DATA_LOAD",
	---(Entity entity), Optional Arg: EntityType - Called after finishing initializing an entity
	POST_ENTITY_DATA_LOAD = "ISAACSAVEMANAGER_POST_ENTITY_DATA_LOAD",
	---() - Called on POST_PLAYER_INIT for the first player, the earliest data can load, to load arbitrary data
	POST_GLOBAL_DATA_LOAD = "ISAACSAVEMANAGER_POST_GLOBAL_DATA_LOAD",
	---(EntityPickup originalPickup, EntityPickup dupedPickup, PickupSave originalSave): boolean, Optional Arg: PickupVariant - Called when a pickup is initialized with the same InitSeed as an existing pickup in the room that has existing save data. Should not run twice for the same pickup. Return `true` to stop data from being copied.
	DUPE_PICKUP_DATA_LOAD = "ISAACSAVEMANAGER_DUPE_PICKUP_DATA_LOAD",
	---(EntityPickup pickup, NoRerollSave saveData), Optional Arg: PickupVariant - Called when the pickup is detected to have an InitSeed change before save data is updated
	PRE_PICKUP_INITSEED_MORPH = "ISAACSAVEMANAGER_PRE_PICKUP_INITSEED_MORPH",
	---(EntityPickup pickup, NoRerollSave saveData), Optional Arg: PickupVariant - Called when the pickup is detected to have an InitSeed change after save data is updated
	POST_PICKUP_INITSEED_MORPH = "ISAACSAVEMANAGER_POST_PICKUP_INITSEED_MORPH",
	---() - Called before all list-indexed room data is reset when changing floors
	PRE_ROOM_DATA_RESET = "ISAACSAVEMANAGER_PRE_ROOM_DATA_RESET",
	---() - Called after all list-indexed room data is reset when changing floors
	POST_ROOM_DATA_RESET = "ISAACSAVEMANAGER_POST_ROOM_DATA_RESET",
	---() - Called before all temporary room data is reset when changing rooms
	PRE_TEMP_DATA_RESET = "ISAACSAVEMANAGER_PRE_TEMP_DATA_RESET",
	---() - Called after all temporary room data is reset when changing rooms
	POST_TEMP_DATA_RESET = "ISAACSAVEMANAGER_POST_TEMP_DATA_RESET",
	---() - Called before all floor data is reset when changing floors
	PRE_FLOOR_DATA_RESET = "ISAACSAVEMANAGER_PRE_FLOOR_DATA_RESET",
	---() - Called after all floor data is reset when changing floors
	POST_FLOOR_DATA_RESET = "ISAACSAVEMANAGER_POST_FLOOR_DATA_RESET",
	---() - Called when Glowing Hourglass is detected to have activated and is queued to reset all save data to the hourglass save
	PRE_GLOWING_HOURGLASS_RESET = "ISAACSAVEMANAGER_PRE_GLOWING_HOURGLASS_RESET",
	---() - Called after Glowing Hourglass reverts all save data has to the hourglass save
	POST_GLOWING_HOURGLASS_RESET = "ISAACSAVEMANAGER_POST_GLOWING_HOURGLASS_RESET"
}

SaveManager.Utility.CustomCallback = {}

for name, value in pairs(SaveManager.SaveCallbacks) do
	SaveManager.Utility.CustomCallback[name] = value
end

SaveManager.Utility.CallbackPriority = {
	IMPORTANT = -1000,
	EARLY = -199,
	LATE = 1000
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
---@field room table @Things in this table are persistent for the current floor and separates data by array of ListIndex.
---@field temp table @Things in this table are persistent only for the current room.
---@field pickupRoom table @Identical to the room save data, but meant specifically for pickups when outside of the room they're stored for.
---@field movingBox table Things in this table are persistent for the entire run, meant for storing pickups that are carried through Moving Box.
---@field treasureRoom table @Things in this table are persistent for the entire run, meant for when you re-visit Treasure Room in the Ascent.
---@field bossRoom table @Things in this table are persistent for the entire run, meant for when you re-visit Boss Room in the Ascent.

---@class PickupSave
---@field InitSeed integer
---@field InitSeedBackup integer
---@field RerollSave table
---@field NoRerollSave table
---@field NoRerollSaveBackup table

---@class FileSave
---@field unlockApi table @Built in compatibility for UnlockAPI (https://github.com/dsju/unlockapi)
---@field deadSeaScrolls table @Built in support for Dead Sea Scrolls (https://github.com/Meowlala/DeadSeaScrollsMenu)
---@field minimapAPI table @Built in support for MinimapAPI(https://github.com/TazTxUK/MinimapAPI)
---@field settings table @Miscellaneous table for anything settings-related.
---@field other table @Miscellaneous table for if you want to use your own unlock system or just need to store random data to the file.

---You can edit what is inside of these tables, but changing the overall structure of this table will break things.
---@class SaveData
SaveManager.DEFAULT_SAVE = {
	game = {
		run = {},
		floor = {},
		room = {},
		temp = {},
		pickupRoom = {},
		movingBox = {},
		treasureRoom = {},
		bossRoom = {},
	},
	gameNoBackup = {
		run = {},
		floor = {},
		room = {},
		temp = {}
	},
	file = {
		unlockApi = {},
		deadSeaScrolls = {},
		minimapAPI = {},
		settings = {},
		other = {}
	}
}

--#region utility methods

---@param ent Entity | EntityType
function SaveManager.Utility.CanHavePersistentData(ent)
	local defaultAllowedTypes = {
		[EntityType.ENTITY_PLAYER] = true,
		[EntityType.ENTITY_FAMILIAR] = true,
		[EntityType.ENTITY_PICKUP] = true,
		[EntityType.ENTITY_SLOT] = true,
		[EntityType.ENTITY_BOMB] = true
	}
	local entType = type(ent) == "number" and ent or ent.Type
	if defaultAllowedTypes[entType] then
		return true
	elseif type(ent) == "userdata" then
		---@cast ent Entity
		return ent:ToNPC() and ent:HasEntityFlags(EntityFlag.FLAG_PERSISTENT)
	elseif entType >= 10 then
		return true
	end
	return false
end

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
function SaveManager.Utility.DebugLog(...)
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
---@param ent? Entity | integer
function SaveManager.Utility.GetDefaultSaveKey(ent)
	if type(ent) == "number" then return "" end
	local typeToName = {
		[EntityType.ENTITY_PLAYER] = "__DEFAULT_PLAYER",
		[EntityType.ENTITY_FAMILIAR] = "__DEFAULT_FAMILIAR",
		[EntityType.ENTITY_PICKUP] = "__DEFAULT_PICKUP",
		[EntityType.ENTITY_SLOT] = "__DEFAULT_SLOT",
		[EntityType.ENTITY_BOMB] = "__DEFAULT_BOMB"
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
---@param ent? Entity | integer
---@param allowSoulSave? boolean
function SaveManager.Utility.GetSaveIndex(ent, allowSoulSave)
	local typeToName = {
		[EntityType.ENTITY_PLAYER] = "PLAYER_",
		--[EntityType.ENTITY_TEAR] = "TEAR_",
		[EntityType.ENTITY_FAMILIAR] = "FAMILIAR_",
		[EntityType.ENTITY_BOMB] = "BOMB_",
		[EntityType.ENTITY_PICKUP] = "PICKUP_",
		[EntityType.ENTITY_SLOT] = "SLOT_",
		--[EntityType.ENTITY_LASER] = "LASER_",
		--[EntityType.ENTITY_KNIFE] = "KNIFE_",
		--[EntityType.ENTITY_PROJECTILE] = "PROJECTILE_"
	}
	local name
	local identifier
	if ent and type(ent) == "userdata" then
		---@cast ent Entity
		if typeToName[ent.Type] then
			name = typeToName[ent.Type]
		else
			name = "NPC_"
		end
		identifier = ent.InitSeed
		if ent:ToPlayer() then
			local player = ent:ToPlayer() ---@cast player EntityPlayer
			local id = 1
			if allowSoulSave then
				player = player:GetSubPlayer() or player
			end
			identifier = tostring(player:GetCollectibleRNG(id):GetSeed())
		elseif ent.Type == EntityType.ENTITY_PICKUP then
			identifier = GetPtrHash(ent)
		end
	elseif ent and type(ent) == "number" then
		name = "GRID_"
		identifier = ent
	elseif not ent then
		name = "GLOBAL"
		identifier = ""
	end
	return name .. identifier
end

function SaveManager.Utility.GetListIndex()
	--Myosotis for checking last floor's ListIndex or for checking the pre-saved ListIndex on continue
	local roomDesc = game:GetLevel():GetCurrentRoomDesc()
	local listIndex = roomDesc.ListIndex
	local isStartOrContinue = (Isaac.GetPlayer() and Isaac.GetPlayer().FrameCount == 0)
	local shouldCheckLastIndex = checkLastIndex or isStartOrContinue or usedHourglass
	if shouldCheckLastIndex then
		listIndex = currentListIndex
	end
	local listIndexString = tostring(listIndex)

	if not shouldCheckLastIndex then
		--Curse of the Maze can swap rooms around
		local SPAWN_SEED = roomDesc.SpawnSeed
		if dataCache.game.room[listIndexString]
			and dataCache.game.room[listIndexString].__SAVEMANAGER_SPAWN_SEED
			and dataCache.game.room[listIndexString].__SAVEMANAGER_SPAWN_SEED ~= SPAWN_SEED
		then
			SaveManager.Utility.DebugLog("Spawn seed doesn't match! Locating correct room..")
			for savedListindex, data in pairs(dataCache.game.room) do
				if data.__SAVEMANAGER_SPAWN_SEED == SPAWN_SEED then
					SaveManager.Utility.DebugLog("Spawn seed located! Swapping room data..")
					local currentData = dataCache.game.room[listIndexString]
					dataCache.game.room[savedListindex] = currentData
					dataCache.game.room[listIndexString] = data
					if dataCache.game.pickupRoom[listIndexString] then
						local currentPickupData = dataCache.game.pickupRoom[listIndexString]
						dataCache.game.pickupRoom[listIndexString] = dataCache.game.pickupRoom[savedListindex]
						dataCache.game.pickupRoom[savedListindex] = currentPickupData
					end
					listIndexString = savedListindex
					break
				end
			end
		end
	end
	return listIndexString
end

function SaveManager.Utility.GetAscentSaveIndex()
	if checkLastIndex then
		local listIndex = tostring(currentListIndex)
		return dataCache.game.room[listIndex] and dataCache.game.room[listIndex].__SAVEMANAGER_ASCENT_INDEX
	elseif game:GetRoom():GetType() == RoomType.ROOM_TREASURE or game:GetRoom():GetType() == RoomType.ROOM_BOSS then
		local level = game:GetLevel()
		local stageType = level:GetStageType()
		stageType = stageType >= StageType.STAGETYPE_REPENTANCE and StageType.STAGETYPE_REPENTANCE or StageType.STAGETYPE_ORIGINAL
		return table.concat({level:GetStage(), stageType, level:GetCurrentRoomDesc().Data.Variant}, "_")
	end
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
		elseif deposit[i] == nil then
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
	for index, value in pairs(tab) do
		if not indexType then
			indexType = type(index)
		end

		if type(index) ~= indexType then
			local valType = type(value) == "userdata" and getmetatable(value).__type or type(value)
			return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.MIXED_TABLES:format(index, tostring(value), valType, indexType)
		end

		if type(index) ~= "string" and type(index) ~= "number" then
			local valType = type(value) == "userdata" and getmetatable(value).__type or type(value)
			return SaveManager.Utility.ValidityState.INVALID,
				SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE:format(index, tostring(value), valType)
		end

		if type(index) == "number" and mFloor(index) ~= index then
			local valType = type(value) == "userdata" and getmetatable(value).__type or type(value)
			return SaveManager.Utility.ValidityState.INVALID,
				SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE:format(index, tostring(value), valType)
		end
	end

	-- check for sparse array
	if isSparseArray(tab) then
		hasWarning = SaveManager.Utility.JsonIncompatibilityType.SPARSE_ARRAY
	end

	if SaveManager.Utility.IsCircular(tab) then
		return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.CIRCULAR_TABLE
	end

	for index, value in pairs(tab) do
		-- check for NaN and infinite values
		-- http://lua-users.org/wiki/InfAndNanComparisons
		if type(value) == "number" then
			if value == math.huge or value == -math.huge or value ~= value then
				return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.NAN_VALUE
			end
		elseif type(value) == "table" then
			local valid, error = SaveManager.Utility.ValidateForJson(value)
			if valid == SaveManager.Utility.ValidityState.INVALID then
				return valid, error
			elseif valid == SaveManager.Utility.ValidityState.VALID_WITH_WARNING then
				hasWarning = error
			end
		elseif type(value) ~= "string" and type(value) ~= "boolean" then
			local valType = type(value) == "userdata" and getmetatable(value).__type or type(value)
			return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.INVALID_VALUE:format(index, tostring(value), valType)
		end
	end

	if hasWarning then
		return SaveManager.Utility.ValidityState.VALID_WITH_WARNING, hasWarning
	end

	return SaveManager.Utility.ValidityState.VALID
end

---@return table | nil
function SaveManager.Utility.RunCallback(callbackId, ...)
	if not modReference then
		SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
		return
	end

	local id = modReference.__SAVEMANAGER_UNIQUE_KEY .. callbackId
	local returnVal = Isaac.RunCallback(id, ...)

	return returnVal
end

---@alias DataDuration "run" | "floor" | "room" | "temp"

---Checks if the entity type with the given save data's duration is permitted within the save manager.
---@param entType integer
---@param saveType DataDuration
function SaveManager.Utility.IsDataTypeAllowed(entType, saveType)
	if type(entType) == "number"
		and not SaveManager.Utility.CanHavePersistentData(entType)
	then
		SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.INVALID_ENTITY_TYPE:format(entType))
		return false
	end
	if type(entType) == "number"
		and entType ~= EntityType.ENTITY_PLAYER
		and entType ~= EntityType.ENTITY_FAMILIAR
		and entType < 10
		and (
			saveType == "run"
			or saveType == "floor"
		)
	then
		SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.INVALID_TYPE_WITH_SAVE:format(entType))
		return false
	end
	return true
end

---@param ignoreWarning? boolean
function SaveManager.Utility.IsDataInitialized(ignoreWarning)
	if not modReference then
		if not ignoreWarning then
			SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.NOT_INITIALIZED)
		end
		return false
	end

	if not loadedData then
		if not ignoreWarning then
			SaveManager.Utility.SendError(SaveManager.Utility.ErrorMessages.DATA_NOT_LOADED)
		end
		return false
	end

	return true
end

-- Returns the dimension ID the player is currently in.
-- 0: Normal Dimension
-- 1: Secondary dimension, used by Downpour mirror dimension and Mines escape sequence
-- 2: Death Certificate dimension
---@param room integer? @The room to check. If nil, the current room will be used. Not needed with REPENTOGON enabled
---@function
function SaveManager.Utility.GetDimension(room)
	local level = game:GetLevel()
	if REPENTOGON then
		return level:GetDimension()
	end
	local roomIndex = room or level:GetCurrentRoomIndex()

	for i = 0, 2 do
		if GetPtrHash(level:GetRoomByIdx(roomIndex, i)) == GetPtrHash(level:GetRoomByIdx(roomIndex, -1)) then
			return i
		end
	end

	return nil
end

--#endregion

--#region default data

---@param saveKey string
---@param saveType DataDuration
---@param data table
---@param noHourglass? boolean
local function addDefaultData(saveKey, saveType, data, noHourglass)
	if not SaveManager.Utility.IsDefaultSaveKey(saveKey) then
		return
	end
	local keyToType = {
		[SaveManager.DefaultSaveKeys.PLAYER] = EntityType.ENTITY_PLAYER,
		[SaveManager.DefaultSaveKeys.FAMILIAR] = EntityType.ENTITY_FAMILIAR,
		[SaveManager.DefaultSaveKeys.PICKUP] = EntityType.ENTITY_PICKUP,
		[SaveManager.DefaultSaveKeys.SLOT] = EntityType.ENTITY_SLOT,
		[SaveManager.DefaultSaveKeys.BOMB] = EntityType.ENTITY_BOMB
	}
	if saveKey ~= SaveManager.DefaultSaveKeys.GLOBAL
		and not SaveManager.Utility.IsDataTypeAllowed(keyToType[saveKey], saveType)
	then
		return
	end

	local gameFile = noHourglass and SaveManager.DEFAULT_SAVE.gameNoBackup or SaveManager.DEFAULT_SAVE.game
	local dataTable = gameFile[saveType]

	---@cast saveKey string
	if dataTable[saveKey] == nil then
		dataTable[saveKey] = {}
	end
	dataTable = dataTable[saveKey]

	SaveManager.Utility.PatchSaveFile(dataTable, data)
	SaveManager.Utility.DebugLog(saveKey, saveType)
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
	addDefaultData(dataType, "temp", data, noHourglass)
end

--#endregion

--#region core methods

function SaveManager.IsLoaded()
	return loadedData
end

---@deprecated
---@param callbackId SaveCallbacks
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

	local newFinalData = SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.PRE_DATA_SAVE, finalData)
	if newFinalData then
		finalData = newFinalData
	end
	if game:GetFrameCount() > 0 then
		finalData.__SAVEMANAGER_LIST_INDEX = currentListIndex
	end

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
function SaveManager.QueueHourglassRestore()
	if shouldRestoreOnUse then
		usedHourglass = true
		skipRoomReset = true
		SaveManager.Utility.DebugLog("Activated glowing hourglass. Data will be reset on new room.")
		Isaac.RunCallback(SaveManager.SaveCallbacks.PRE_GLOWING_HOURGLASS_RESET)
	end
end

-- Restores the game save with the data in the hourglass backup.
function SaveManager.TryHourglassRestore()
	if usedHourglass then
		local newData = SaveManager.Utility.DeepCopy(hourglassBackup)
		dataCache.game = SaveManager.Utility.PatchSaveFile(newData, SaveManager.DEFAULT_SAVE.game)
		usedHourglass = false
		SaveManager.Utility.DebugLog("Restored data from Glowing Hourglass")
		Isaac.RunCallback(SaveManager.SaveCallbacks.POST_GLOWING_HOURGLASS_RESET)
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

	local newSaveData = SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.PRE_DATA_LOAD, saveData,
		isLuamod)
	if newSaveData then
		saveData = newSaveData
	end

	if game:GetFrameCount() > 0 then
		currentListIndex = saveData.__SAVEMANAGER_LIST_INDEX or Game():GetLevel():GetCurrentRoomDesc().ListIndex
		saveData.__SAVEMANAGER_LIST_INDEX = nil
	end

	dataCache = saveData
	--Would only fail to exist if you continued a run before creating save data for the first time
	if dataCache.hourglassBackup then
		hourglassBackup = SaveManager.Utility.DeepCopy(dataCache.hourglassBackup)
	else
		hourglassBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE)
	end

	loadedData = true
	inRunButNotLoaded = false

	SaveManager.Utility.RunCallback(SaveManager.Utility.CustomCallback.POST_DATA_LOAD, saveData, isLuamod)
end

---Gets a unique string as an identifier for the pickup when outside of the room it's present in.
---@param pickup EntityPickup
function SaveManager.Utility.GetPickupIndex(pickup)
	local index = table.concat(
		{ "PICKUP_ROOMDATA",
			mFloor(pickup.Position.X),
			mFloor(pickup.Position.Y),
			pickup.InitSeed },
		"_")
	if myosotisCheck or movingBoxCheck then
		--Trick code to pulling previous floor's data only if initseed matches.
		--Even with dupe initseeds pickups spawning, it'll go through and init data for each one
		SaveManager.Utility.DebugLog("Data active for a transferred pickup. Attempting to find data...")
		local targetTable = myosotisCheck and hourglassBackup.pickupRoom or dataCache.game.movingBox
		if myosotisCheck then
			local listIndex = SaveManager.Utility.GetListIndex()
			if targetTable[listIndex] then
				targetTable = targetTable[listIndex]
			end
		end
		for backupIndex, _ in pairs(targetTable) do
			local initSeed = pickup.InitSeed

			if string.sub(backupIndex, -string.len(tostring(initSeed)), -1) == tostring(initSeed) then
				index = backupIndex
				SaveManager.Utility.DebugLog("Stored data found for",
					SaveManager.Utility.GetSaveIndex(pickup) .. ".")
				break
			end
		end
	end
	return index
end

---Gets the pickup's persistent data for the floor to keep track of it outside rooms.
---Also checks if was stored inside the boss or treasure room save data used for the Ascent.
---
---You won't use this yourself as the pickup's persistent data is immediately nulled once the pickup in the room is loaded in. Use `GetFloorSave` instead.
---@param pickup EntityPickup
---@return table?, string
function SaveManager.Utility.GetPickupData(pickup)
	local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
	local listIndex = SaveManager.Utility.GetListIndex()
	local pickupDataRoot = dataCache.game.pickupRoom[listIndex]
	if myosotisCheck then
		pickupDataRoot = hourglassBackup.pickupRoom[listIndex]
	elseif movingBoxCheck then
		pickupDataRoot = dataCache.game.movingBox
	end
	local pickupData = pickupDataRoot and pickupDataRoot[pickupIndex]

	if not pickupData and game:GetLevel():IsAscent() then
		SaveManager.Utility.DebugLog("Was unable to locate pickup room data. Searching Ascent...")
		local roomType = game:GetRoom():GetType()
		local ascentIndex = SaveManager.Utility.GetAscentSaveIndex()
		if not ascentIndex then return pickupData, pickupIndex end
		if roomType == RoomType.ROOM_BOSS then
			pickupData = dataCache.game.bossRoom[ascentIndex] and dataCache.game.bossRoom[ascentIndex][pickupIndex]
		elseif roomType == RoomType.ROOM_TREASURE then
			pickupData = dataCache.game.treasureRoom[ascentIndex] and dataCache.game.treasureRoom[ascentIndex][pickupIndex]
		end
	end
	return pickupData, pickupIndex
end

---When leaving the room, stores floor-persistent pickup data.
---@param pickup EntityPickup
local function storePickupData(pickup)
	local listIndex = SaveManager.Utility.GetListIndex()
	local saveIndex = SaveManager.Utility.GetSaveIndex(pickup)
	local pickupDataRoot = dataCache.game.room
	local roomPickupData = pickupDataRoot[listIndex] and pickupDataRoot[listIndex][saveIndex]
	if not roomPickupData then
		SaveManager.Utility.DebugLog("Failed to find room data for", saveIndex,
			"in ListIndex", listIndex)
		return
	end
	local pickupIndex = SaveManager.Utility.GetPickupIndex(pickup)
	if movingBoxCheck then
		dataCache.game.movingBox[pickupIndex] = roomPickupData
		SaveManager.Utility.DebugLog("Stored Moving Box pickup data for", pickupIndex)
	else
		local pickupRoomSave = dataCache.game.pickupRoom[listIndex]
		if not pickupRoomSave then
			local newSave = {}
			dataCache.game.pickupRoom[listIndex] = newSave
			pickupRoomSave = newSave
		end
		pickupRoomSave[pickupIndex] = roomPickupData
		SaveManager.Utility.DebugLog("Stored pickup data for", pickupIndex)
		dataCache.game.room[listIndex][saveIndex] = nil
	end
end

local bossAscentSaveIndexes = {}

local function tryPopulateAscentData(listIndex, saveIndex)
	local roomType = game:GetRoom():GetType()

	SaveManager.Utility.DebugLog("Attempting to locate Ascent save data for", saveIndex)
	local ascentData = roomType == RoomType.ROOM_BOSS and dataCache.game.bossRoom or dataCache.game.treasureRoom
	local ascentIndex = SaveManager.Utility.GetAscentSaveIndex()
	if not ascentIndex then return end
	local ascentRoomData = ascentData[ascentIndex]
	if not ascentRoomData then return end
	local ascentSaveData = ascentRoomData[saveIndex]

	if ascentSaveData then
		SaveManager.Utility.DebugLog("Found Ascent data for", saveIndex, ". Populating...")
		local saveData = dataCache.game.room[listIndex]
		if not saveData then
			local newData = {}
			dataCache.game.room[listIndex] = newData
			saveData = newData
		end
		saveData[saveIndex] = ascentSaveData
		if roomType == RoomType.ROOM_BOSS then
			dataCache.game.bossRoom[ascentIndex][saveIndex] = nil
			table.insert(bossAscentSaveIndexes, saveIndex)
		elseif roomType == RoomType.ROOM_TREASURE then
			dataCache.game.treasureRoom[ascentIndex][saveIndex] = nil
		end
	else
		SaveManager.Utility.DebugLog("Failed to find Ascent data for", ascentIndex, saveIndex)
	end
end

---When re-entering a room, gives back floor-persistent data to valid pickups.
---@param pickup EntityPickup
local function populatePickupData(pickup)
	local pickupData, pickupIndex = SaveManager.Utility.GetPickupData(pickup)
	local listIndex = SaveManager.Utility.GetListIndex()
	local saveIndex = SaveManager.Utility.GetSaveIndex(pickup)

	if dataCache.game.room[listIndex] == nil then
		dataCache.game.room[listIndex] = {}
	end
	if pickupData then
		dataCache.game.room[listIndex][saveIndex] = pickupData
		SaveManager.Utility.DebugLog("Successfully populated pickup data of index", saveIndex,
			"in ListIndex",
			listIndex)
		if movingBoxCheck then
			dataCache.game.movingBox[pickupIndex] = nil
		elseif dataCache.game.pickupRoom[listIndex] then
			dataCache.game.pickupRoom[listIndex][pickupIndex] = nil
		end
		if game:GetLevel():IsAscent() then
			local roomType = game:GetRoom():GetType()
			local ascentSaveIndex = SaveManager.Utility.GetAscentSaveIndex()
			if not ascentSaveIndex then return end
			if roomType == RoomType.ROOM_BOSS and dataCache.game.bossRoom[ascentSaveIndex] then
				dataCache.game.bossRoom[ascentSaveIndex][pickupIndex] = nil
				table.insert(bossAscentSaveIndexes, saveIndex)
			elseif roomType == RoomType.ROOM_TREASURE and dataCache.game.treasureRoom[ascentSaveIndex] then
				dataCache.game.treasureRoom[ascentSaveIndex][pickupIndex] = nil
			end
		end
	else
		local dupedPickup = pickup
		local ptrHash1 = GetPtrHash(dupedPickup)
		dupeTaggedPickups[ptrHash1] = true
		for _, originalPickup in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, dupedPickup.Variant)) do
			local ptrHash2 = GetPtrHash(originalPickup)

			if originalPickup.FrameCount > 0
				and originalPickup.InitSeed == dupedPickup.InitSeed
				and not dupeTaggedPickups[ptrHash2]
			then
				SaveManager.Utility.DebugLog("Identified duplicate InitSeed pickup. Attempting to copy data...")
				dupeTaggedPickups[ptrHash2] = true
				local originalSaveIndex = SaveManager.Utility.GetSaveIndex(originalPickup)
				local originalSaveData = dataCache.game.room[listIndex][originalSaveIndex]
				if originalSaveData then
					local result = Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.DUPE_PICKUP_DATA_LOAD, originalPickup.Variant, originalPickup, dupedPickup, originalSaveData)
					if not result then
						SaveManager.Utility.DebugLog("Duplicate data copied!")
						dataCache.game.room[listIndex][saveIndex] = SaveManager.Utility.DeepCopy(originalSaveData)
					else
						SaveManager.Utility.DebugLog("Duplicate data prevented from being copied")
					end
				end
				return
			end
		end
		SaveManager.Utility.DebugLog("Failed to find pickup data for index", pickupIndex, "in ListIndex",
			listIndex)
	end
end

local function checkForMyosotis()
	if REPENTOGON then
		myosotisCheck = PlayerManager.AnyoneHasTrinket(TrinketType.TRINKET_MYOSOTIS)
	else
		for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_PLAYER)) do
			local player = ent:ToPlayer()
			if player and player:HasTrinket(TrinketType.TRINKET_MYOSOTIS) then
				myosotisCheck = true
				break
			end
		end
	end
end

local function checkForAscentValidRooms()
	allowedAscentRooms = {}
	local rooms = game:GetLevel():GetRooms()

	for listIndex = 0, #rooms - 1 do
		local roomDesc = rooms:Get(listIndex)
		if (roomDesc.Data.Type == RoomType.ROOM_TREASURE
			or roomDesc.Data.Type == RoomType.ROOM_BOSS)
			and SaveManager.Utility.GetDimension(roomDesc.SafeGridIndex) == 0
		then
			allowedAscentRooms[tostring(listIndex)] = true
		end
	end
end

local function storeAndPopulateAscent()
	local currentRoomDesc = game:GetLevel():GetCurrentRoomDesc()
	if not game:GetLevel():IsAscent() then
		if currentListIndex ~= game:GetLevel():GetCurrentRoomDesc().ListIndex then
			checkLastIndex = true
		end
		local listIndex = SaveManager.Utility.GetListIndex()
		if not allowedAscentRooms[listIndex] then
			SaveManager.Utility.DebugLog("Room at index", listIndex, "is not valid for Ascent")
			checkLastIndex = false
			return
		end
		local roomSaveData = dataCache.game.room[listIndex]

		if roomSaveData and roomSaveData.__SAVEMANAGER_ASCENT_ROOM_TYPE then
			local roomType = roomSaveData.__SAVEMANAGER_ASCENT_ROOM_TYPE
			SaveManager.Utility.DebugLog("Index", listIndex, "is a Treasure/Boss room. Storing all room data")
			local targetTable = roomType == RoomType.ROOM_TREASURE and dataCache.game.treasureRoom or dataCache.game.bossRoom
			local ascentIndex = SaveManager.Utility.GetAscentSaveIndex()
			if not ascentIndex then return end
			if not targetTable[ascentIndex] then
				targetTable[ascentIndex] = {}
			end
			local ascentRoomData = targetTable[ascentIndex]
			if roomSaveData then
				for saveIndex, saveData in pairs(roomSaveData) do
					if not string.find(saveIndex, "__") and not string.find(saveIndex, "PICKUP") then
						ascentRoomData[saveIndex] = saveData
					end
				end
			end
			local pickupSaveData = dataCache.game.pickupRoom[listIndex]
			if pickupSaveData then
				for saveIndex, saveData in pairs(pickupSaveData) do
					ascentRoomData[saveIndex] = saveData
				end
			end
		end
		checkLastIndex = false
	elseif currentRoomDesc.Data.Type == RoomType.ROOM_TREASURE
		or currentRoomDesc.Data.Type == RoomType.ROOM_BOSS
	then
		SaveManager.Utility.DebugLog("Treasure/Boss Ascent room detected. Transferring all stored data...")
		local targetTable = currentRoomDesc.Data.Type == RoomType.ROOM_TREASURE and dataCache.game.treasureRoom or dataCache.game.bossRoom
		local ascentIndex = SaveManager.Utility.GetAscentSaveIndex()
		if not ascentIndex then return end
		local ascentRoomData = targetTable[ascentIndex]
		if not ascentRoomData then return end
		local listIndex = SaveManager.Utility.GetListIndex()
		local roomSaveData = dataCache.game.room[listIndex]
		if not roomSaveData then
			local newData = {}
			dataCache.game.room[listIndex] = newData
			roomSaveData = newData
		end
		if ascentRoomData then
			for saveIndex, saveData in pairs(ascentRoomData) do
				roomSaveData[saveIndex] = saveData
				if currentRoomDesc.Data.Type == RoomType.ROOM_BOSS then
					table.insert(bossAscentSaveIndexes, saveIndex)
				end
			end
			targetTable[ascentIndex] = nil
		else
			SaveManager.Utility.DebugLog("Failed to find Ascent data for index", ascentIndex)
		end
	end
end

--#endregion

--#region game start/entity init

local function onGameLoad()
	if game:GetFrameCount() == 0 then
		skipFloorReset = true
	end
	skipRoomReset = true
	SaveManager.Load(false)
	loadedData = true
	inRunButNotLoaded = false
	dontSaveModData = false
end

---@param ent? Entity
local function onEntityInit(_, ent)
	local newGame = game:GetFrameCount() == 0 and not ent
	local defaultSaveIndex = SaveManager.Utility.GetSaveIndex(ent)
	local altSaveIndex = SaveManager.Utility.GetSaveIndex(ent, true)
	local defaultKey = SaveManager.Utility.GetDefaultSaveKey(ent)
	checkLastIndex = false

	if not loadedData or inRunButNotLoaded then
		SaveManager.Utility.DebugLog("Game Init")
		onGameLoad()
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
	local function implementSaveKeys(tab, target, history, saveIndex)
		history = history or {}
		for i, v in pairs(tab) do
			if i == defaultKey then
				local targetTable = reconstructHistory(target, history)
				if targetTable and not targetTable[saveIndex] then
					SaveManager.Utility.DebugLog("Attempting default data transfer")
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
						SaveManager.Utility.DebugLog("Default data copied for", saveIndex)
					else
						SaveManager.Utility.DebugLog("No default data found for", saveIndex)
					end
					targetTable[i] = nil
				else
					SaveManager.Utility.DebugLog(
						"Was unable to fetch target table or data is already loaded for",
						saveIndex)
				end
			elseif type(v) == "table" then
				table.insert(history, i)
				implementSaveKeys(v, target, history, saveIndex)
				table.remove(history)
			end
		end
		return target
	end

	local listIndex = SaveManager.Utility.GetListIndex()
	local function resetNoRerollData(targetTable, defaultTable, checkIndex)
		if checkIndex and targetTable[listIndex] then
			targetTable = targetTable[listIndex]
		end
		local data = targetTable[defaultSaveIndex]
		if data and ent and data.InitSeed and data.InitSeed ~= ent.InitSeed then
			Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.PRE_PICKUP_INITSEED_MORPH, ent.Variant, ent, data.NoRerollSave)
			if data.InitSeedBackup and ent.InitSeed == data.InitSeedBackup then
				local backupSave = data.NoRerollSaveBackup
				local initSeed = data.InitSeedBackup
				data.NoRerollSaveBackup = SaveManager.Utility.DeepCopy(data.NoRerollSave)
				data.InitSeedBackup = data.InitSeed
				data.NoRerollSave = backupSave
				data.InitSeed = initSeed
				SaveManager.Utility.DebugLog("Detected flip in", defaultSaveIndex, "! Restored backup NoRerollSave.")
				Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.POST_PICKUP_INITSEED_MORPH, ent.Variant, ent, data.NoRerollSave)
				return
			end
			data.NoRerollSaveBackup = SaveManager.Utility.DeepCopy(data.NoRerollSave)
			data.InitSeedBackup = data.InitSeed
			data.NoRerollSave = SaveManager.Utility.PatchSaveFile({}, defaultTable)
			data.InitSeed = ent.InitSeed
			SaveManager.Utility.DebugLog("Detected init seed change in", defaultSaveIndex,
				"! NoRerollSave has been reset")
			Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.POST_PICKUP_INITSEED_MORPH, ent.Variant, ent, data.NoRerollSave)
		end
	end
	if ent and ent.Type == EntityType.ENTITY_PICKUP then
		local pickup = ent:ToPickup()
		---@cast pickup EntityPickup
		populatePickupData(pickup)
	elseif game:GetLevel():IsAscent()
		and game:GetRoom():IsFirstVisit()
		and (game:GetRoom():GetType() == RoomType.ROOM_BOSS
		or game:GetRoom():GetType() == RoomType.ROOM_TREASURE
	) then
		tryPopulateAscentData(listIndex, defaultSaveIndex)
	end
	if defaultKey then
		implementSaveKeys(SaveManager.DEFAULT_SAVE.game, dataCache.game, nil, defaultSaveIndex)
		implementSaveKeys(SaveManager.DEFAULT_SAVE.gameNoBackup, dataCache.gameNoBackup, nil, defaultSaveIndex)
	end
	if ent and ent:ToPlayer() and ent:ToPlayer():GetSubPlayer() then
		implementSaveKeys(SaveManager.DEFAULT_SAVE.game, dataCache.game, nil, altSaveIndex)
		implementSaveKeys(SaveManager.DEFAULT_SAVE.gameNoBackup, dataCache.gameNoBackup, nil, altSaveIndex)
	end
	if ent and ent.Type == EntityType.ENTITY_PICKUP then
		resetNoRerollData(dataCache.game.temp, SaveManager.DEFAULT_SAVE.game.temp)
		resetNoRerollData(dataCache.game.room, SaveManager.DEFAULT_SAVE.game.room, true)
		resetNoRerollData(dataCache.gameNoBackup.temp, SaveManager.DEFAULT_SAVE.gameNoBackup.temp)
		resetNoRerollData(dataCache.gameNoBackup.room, SaveManager.DEFAULT_SAVE.gameNoBackup.room, true)
	end
	if not ent then
		Isaac.RunCallback(SaveManager.SaveCallbacks.POST_GLOBAL_DATA_LOAD)
	else
		Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.POST_ENTITY_DATA_LOAD, ent.Type, ent)
	end
end

--#endregion

--#region luamod

local function detectLuamod()
	if not loadedData and inRunButNotLoaded
		and (REPENTOGON and (not dontSaveModData and Isaac.GetFrameCount() > 0 and Console.GetHistory()[2] == "Success!")
			or game:GetFrameCount() > 0)
	then
		if game:GetFrameCount() > 0 then
			currentListIndex = game:GetLevel():GetCurrentRoomDesc().ListIndex
		end
		SaveManager.Load(true)
		inRunButNotLoaded = false
		shouldRestoreOnUse = true
	end
end

--#endregion

--#region reset data

--A safety precaution to make sure data for entities that no longer exist are removed from room data.
local function tryRemoveLeftoverData()
	SaveManager.Utility.DebugLog("leftover ent data check")
	local availableIndexes = {}
	for _, ent in ipairs(Isaac.GetRoomEntities()) do
		if SaveManager.Utility.CanHavePersistentData(ent) then
			availableIndexes[SaveManager.Utility.GetSaveIndex(ent)] = true
		end
	end
	local function removeLeftoverData(tab, isRoom)
		if isRoom then
			local listIndex = SaveManager.Utility.GetListIndex()
			if tab[listIndex] then
				tab = tab[listIndex]
			else
				return
			end
		end
		for key, _ in pairs(tab) do
			local specialData = string.find(key, "__")
			if key ~= "GLOBAL"
				and not specialData
				and not availableIndexes[key]
			then
				SaveManager.Utility.DebugLog("Leftover", isRoom and "room" or "temp", "data removed for", key)
				tab[key] = nil
			end
		end
	end
	removeLeftoverData(dataCache.game.temp)
	removeLeftoverData(dataCache.gameNoBackup.temp)
	removeLeftoverData(dataCache.game.room, true)
	removeLeftoverData(dataCache.gameNoBackup.room, true)
end

---@param saveType string
local function resetData(saveType)
	if (not skipRoomReset and saveType == "temp") or (not skipFloorReset and (saveType == "room" or saveType == "floor")) then
		local typeToCallback = {
			temp = {SaveManager.SaveCallbacks.PRE_TEMP_DATA_RESET, SaveManager.SaveCallbacks.POST_TEMP_DATA_RESET},
			room = {SaveManager.SaveCallbacks.PRE_ROOM_DATA_RESET, SaveManager.SaveCallbacks.POST_ROOM_DATA_RESET},
			floor = {SaveManager.SaveCallbacks.PRE_FLOOR_DATA_RESET, SaveManager.SaveCallbacks.POST_FLOOR_DATA_RESET}
		}
		Isaac.RunCallback(typeToCallback[saveType][1])
		local transferBossAscentData = {}
		local listIndex = SaveManager.Utility.GetListIndex()
		if saveType ~= "temp" and game:GetLevel():IsAscent() then
			--Search for any data that was recently created on init before floor reset to put back into the room save
			for _, index in ipairs(bossAscentSaveIndexes) do
				local listIndexSave = dataCache.game.room[listIndex]
				if listIndexSave and listIndexSave[index] then
					SaveManager.Utility.DebugLog("Found boss ascent backup data for", index,
						". Storing data for carry over after reset...")
					transferBossAscentData[index] = listIndexSave[index]
					listIndexSave[index] = nil
				else
					SaveManager.Utility.DebugLog("No data found for", saveType, listIndex, index)
				end
			end
			bossAscentSaveIndexes = {}
		end
		if saveType == "temp" and listIndex ~= "509" then
			--room data from goto commands should be removed, as if it were a room save. It is not persistent.
			if dataCache.game.room["509"] then
				dataCache.game.room["509"] = nil
			end
			if dataCache.gameNoBackup.room["509"] then
				dataCache.gameNoBackup.room["509"] = nil
			end
		end
		dataCache.game[saveType] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game[saveType])
		dataCache.gameNoBackup[saveType] = SaveManager.Utility.PatchSaveFile({},
			SaveManager.DEFAULT_SAVE.gameNoBackup[saveType])
		for index, data in pairs(transferBossAscentData) do
			if not dataCache.game.room[listIndex] then
				dataCache.game.room[listIndex] = {}
			end
			dataCache.game.room[listIndex][index] = data
			SaveManager.Utility.DebugLog("Saved data from reset, index", index)
		end
		SaveManager.Utility.DebugLog("reset", saveType, "data")
		shouldRestoreOnUse = true
		Isaac.RunCallback(typeToCallback[saveType][2])
	end
	if saveType == "temp" then
		skipRoomReset = false
	elseif saveType == "floor" then
		skipFloorReset = false
	end
end

local saveFileWait = 3

local function preGameExit(_, shouldSave)
	SaveManager.Utility.DebugLog("pre game exit")

	if shouldSave then
		for _, pickup in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
			if type(pickup) ~= "number" then
				---@cast pickup EntityPickup
				storePickupData(pickup)
			end
		end
	else
		dataCache.game = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		dataCache.gameNoBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup)
		hourglassBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
	end
	SaveManager.Save()
	inRunButNotLoaded = false
	shouldRestoreOnUse = false
	dontSaveModData = true
	saveFileWait = 0
end

---@param ent Entity
local function postEntityRemove(_, ent)
	if not dataCache.game
		or not SaveManager.Utility.CanHavePersistentData(ent)
	then
		return
	end

	if (game:IsPaused() and game:GetRoom():GetFrameCount() == 0) or (ent.Type == EntityType.ENTITY_PICKUP and movingBoxCheck) then
		--Although entities are removed from the previous room and this happens before POST_NEW_ROOM...
		--Some data from the new room is already loaded, such as frame count and listindex.
		if currentListIndex ~= game:GetLevel():GetCurrentRoomDesc().ListIndex then
			checkLastIndex = true
		end
		if ent.Type == EntityType.ENTITY_PICKUP then
			---@cast ent EntityPickup
			storePickupData(ent)
		end
		return
	end
	local defaultSaveIndex = SaveManager.Utility.GetSaveIndex(ent)
	---@param tab GameSave
	local function removeSaveData(tab, saveIndex)
		for saveType, dataTable in pairs(tab) do
			if saveType == "room" and dataTable[SaveManager.Utility.GetListIndex()] then
				removeSaveData(dataTable)
			elseif dataTable[saveIndex] then
				SaveManager.Utility.DebugLog("Removed data", saveIndex)
				dataTable[saveIndex] = nil
			end
		end
	end
	removeSaveData(dataCache.game, defaultSaveIndex)
	removeSaveData(dataCache.gameNoBackup, defaultSaveIndex)
	if ent:ToPlayer() and ent:ToPlayer():GetSubPlayer() then
		local altSaveIndex = SaveManager.Utility.GetSaveIndex(ent, true)
		removeSaveData(dataCache.game, altSaveIndex)
		removeSaveData(dataCache.gameNoBackup, altSaveIndex)
	end
end

--#endregion

--#region core callbacks

local function postSlotInitNoRGON()
	for _, slot in ipairs(Isaac.FindByType(EntityType.ENTITY_SLOT)) do
		if type(slot) ~= "number" and slot.FrameCount <= 1 then
			onEntityInit(_, slot)
		end
	end
end

local function postNewRoom()
	SaveManager.Utility.DebugLog("new room")
	if not REPENTOGON then
		postSlotInitNoRGON()
	end
	local currentRoomDesc = game:GetLevel():GetCurrentRoomDesc()
	storeAndPopulateAscent()
	currentListIndex = currentRoomDesc.ListIndex
	resetData("temp")
	tryRemoveLeftoverData()
	if not SaveManager.AutoCreateRoomSaves then return end
	local roomSaveData = SaveManager.GetRoomSave(nil, false, currentListIndex)
	--Always keep track of for Curse of the Maze
	roomSaveData.__SAVEMANAGER_SPAWN_SEED = currentRoomDesc.SpawnSeed
	local roomType = currentRoomDesc.Data.Type
	--For knowing what the last room was after travelling down a floor in the same room
	--Doesn't matter if its not boss/treasure
	if roomType == RoomType.ROOM_BOSS or roomType == RoomType.ROOM_TREASURE then
		roomSaveData.__SAVEMANAGER_ROOM_TYPE = currentRoomDesc.Data.Type
	end
	--To know which boss/treasure room is on what floor. Nil if not either room type
	roomSaveData.__SAVEMANAGER_ASCENT_INDEX = SaveManager.Utility.GetAscentSaveIndex()
end

local function postNewLevel()
	SaveManager.Utility.DebugLog("new level")
	resetData("room")
	resetData("floor")
	checkForMyosotis()
	checkForAscentValidRooms()
	SaveManager.Save()
end

local function postUpdate()
	--Shockingly, this triggers for one frame when doing a room transition
	if not REPENTOGON and game:IsPaused() then
		if usedHourglass then
			SaveManager.TryHourglassRestore()
		else
			hourglassBackup = SaveManager.Utility.DeepCopy(dataCache.game)
		end
	end
	myosotisCheck = false
	movingBoxCheck = false
	dupeTaggedPickups = {}
end

---With REPENTOGON, allows you to load data whenever you select a save slot.
---@param isSlotSelected boolean
local function postSaveSlotLoad(_, _, isSlotSelected, _)
	if not isSlotSelected then
		return
	end
	if saveFileWait < 3 then
		saveFileWait = saveFileWait + 1
	else
		SaveManager.Load(false)
	end
end

--#endregion

--#region init logic

-- Initializes the save manager.
---@param mod table @The reference to your mod. This is the table that is returned when you call `RegisterMod`.
function SaveManager.Init(mod)
	modReference = mod

	-- Priority callbacks put in place to load data early and save data late.

	--Global data
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_PLAYER_INIT, SaveManager.Utility.CallbackPriority.IMPORTANT,
		function(_, player)
			if GetPtrHash(player) == GetPtrHash(Isaac.GetPlayer()) then
				inRunButNotLoaded = true
			end
			onEntityInit()
		end
	)

	local initCallbacks = {
		ModCallbacks.MC_POST_PLAYER_INIT,
		ModCallbacks.MC_FAMILIAR_INIT,
		ModCallbacks.MC_POST_PICKUP_INIT,
		ModCallbacks.MC_POST_BOMB_INIT,
		ModCallbacks.MC_POST_NPC_INIT,
	}

	for _, initCallback in ipairs(initCallbacks) do
		modReference:AddPriorityCallback(initCallback, SaveManager.Utility.CallbackPriority.IMPORTANT, onEntityInit)
	end

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, SaveManager.Utility.CallbackPriority.EARLY, postUpdate)

	if REPENTOGON then
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_SLOT_INIT, SaveManager.Utility.CallbackPriority.IMPORTANT,
			onEntityInit)
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD,
			SaveManager.Utility.CallbackPriority.IMPORTANT, postSaveSlotLoad)
		modReference:AddPriorityCallback(ModCallbacks.MC_MENU_INPUT_ACTION,
			SaveManager.Utility.CallbackPriority.IMPORTANT, function()
				local success, currentMenu = pcall(MenuManager.GetActiveMenu)
				if not success then return end
				dontSaveModData = currentMenu == MainMenuType.TITLE or
					currentMenu == MainMenuType.MODS
				detectLuamod()
			end)
		modReference:AddCallback(ModCallbacks.MC_PRE_GLOWING_HOURGLASS_SAVE, function(_, slot)
			hourglassBackup = SaveManager.Utility.DeepCopy(dataCache.game)
		end)
		modReference:AddCallback(ModCallbacks.MC_PRE_GLOWING_HOURGLASS_LOAD, function(_, slot)
			SaveManager.QueueHourglassRestore()
			SaveManager.TryHourglassRestore()
		end)
	else
		modReference:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, SaveManager.Utility.CallbackPriority.EARLY,
			SaveManager.QueueHourglassRestore,
			CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
		)
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, SaveManager.Utility.CallbackPriority.IMPORTANT,
			postSlotInitNoRGON)
	end

	if REPENTOGON then
		local function tryDetectLuamod()
			dontSaveModData = false
			detectLuamod()
			if loadedData then
				Isaac.RemoveCallback(modReference, ModCallbacks.MC_INPUT_ACTION, tryDetectLuamod)
			end
		end
		--load luamod as early as possible.
		modReference:AddPriorityCallback(ModCallbacks.MC_INPUT_ACTION, SaveManager.Utility.CallbackPriority.IMPORTANT,
			tryDetectLuamod)
	else
		local deathCallbacks = {
			ModCallbacks.MC_POST_NPC_RENDER,
			ModCallbacks.MC_POST_EFFECT_RENDER,
			ModCallbacks.MC_POST_PICKUP_RENDER,
			ModCallbacks.MC_POST_PLAYER_RENDER
		}
		local function pleaseEndMe()
			dontSaveModData = false
			detectLuamod()
			if loadedData then
				for _, deathCallback in ipairs(deathCallbacks) do
					Isaac.RemoveCallback(modReference, deathCallback, pleaseEndMe)
				end
			end
		end
		for _, deathCallback in ipairs(deathCallbacks) do
			modReference:AddPriorityCallback(deathCallback, SaveManager.Utility.CallbackPriority.IMPORTANT,	pleaseEndMe)
		end
	end

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, SaveManager.Utility.CallbackPriority.EARLY,
		postNewRoom)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_NEW_LEVEL, SaveManager.Utility.CallbackPriority.EARLY,
		postNewLevel)
	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, SaveManager.Utility.CallbackPriority.LATE,
		preGameExit)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, SaveManager.Utility.CallbackPriority.LATE,
		postEntityRemove)
	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_USE_ITEM, SaveManager.Utility.CallbackPriority.LATE,
		function()
			movingBoxCheck = true
		end,
		CollectibleType.COLLECTIBLE_MOVING_BOX
	)

	modReference:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, SaveManager.Utility.CallbackPriority.EARLY,
		function()
			movingBoxCheck = false
		end,
		CollectibleType.COLLECTIBLE_MOVING_BOX
	)

	modReference:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, SaveManager.Utility.CallbackPriority.LATE,
		function()
			SaveManager.Save()
		end,
		CollectibleType.COLLECTIBLE_GENESIS
	)

	-- used to detect if an unloaded mod is this mod for when saving for luamod and for unique per-mod callbacks
	modReference.__SAVEMANAGER_UNIQUE_KEY = ("%s-%s"):format(Random(), Random())

	for name, value in pairs(SaveManager.SaveCallbacks) do
		SaveManager.SaveCallbacks[name] = modReference.__SAVEMANAGER_UNIQUE_KEY .. value
	end

	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, SaveManager.Utility.CallbackPriority.EARLY,
		function(_, modToUnload)
			if modToUnload.__SAVEMANAGER_UNIQUE_KEY and modToUnload.__SAVEMANAGER_UNIQUE_KEY == modReference.__SAVEMANAGER_UNIQUE_KEY
				and loadedData
				and not dontSaveModData
			then
				saveFileWait = 0
				SaveManager.Save()
			end
		end
	)
end

--#endregion

--#region MinimapAI integration

-- Registers MinimapAPI as a dependent of SaveManager.
---@param minimapAPI table @Reference to MinimapAPI.
---@param branchVersion table @The version of the branch you are using for MinimapAPI.
function SaveManager.InitMinimapAPI(minimapAPI, branchVersion)
	if not SaveManager.Utility.IsDataInitialized() then return end
	if minimapAPI.BranchVersion == branchVersion then
		minimapAPI.DisableSaving = true
		minimapAPIReference = minimapAPI
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, SaveManager.Utility.CallbackPriority.IMPORTANT, function(_, isContinue)
			if modReference:HasData() and MinimapAPI.BranchVersion == branchVersion then
				MinimapAPI:LoadSaveTable(SaveManager.GetMinimapAPISave(), isContinue)
			end
		end)
		modReference:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, SaveManager.Utility.CallbackPriority.LATE - 1, function(_, shouldSave)
			if minimapAPIReference then
				dataCache.file.minimapAPI = minimapAPIReference:GetSaveTable(shouldSave)
			end
		end)
	end
end

--#endregion

--#region save methods

-- Returns the entire save table, including the file save.
function SaveManager.GetEntireSave()
	return dataCache
end

---@param ent? Entity | integer
---@param noHourglass false|boolean?
---@param initDataIfNotPresent? boolean
---@param saveType DataDuration
---@param listIndex? integer
---@param allowSoulSave? boolean
---@return table
local function getRespectiveSave(ent, noHourglass, initDataIfNotPresent, saveType, listIndex, allowSoulSave)
	if not SaveManager.Utility.IsDataInitialized(not initDataIfNotPresent)
		---@diagnostic disable-next-line: undefined-field
		or (ent and type(ent) == "userdata" and not SaveManager.Utility.IsDataTypeAllowed(ent.Type, saveType))
	then
		---@diagnostic disable-next-line: missing-return-value
		return
	end
	noHourglass = noHourglass or false

	local getAltSave = allowSoulSave
		and ent
		and type(ent) == "userdata"
		---@cast ent Entity
		and ent:ToPlayer()
		and ent:ToPlayer():GetPlayerType() == PlayerType.PLAYER_THESOUL
		and ent:ToPlayer():GetSubPlayer() ~= nil
	local saveTableBackup = dataCache.game[saveType]
	local saveTableNoBackup = dataCache.gameNoBackup[saveType]
	local saveTable = noHourglass and saveTableNoBackup or saveTableBackup

	if not saveTable then return saveTable end
	local numberListIndex = listIndex or tonumber(SaveManager.Utility.GetListIndex())
	local stringListIndex = tostring(numberListIndex)
	if saveType == "room" then
		if not saveTable[stringListIndex] then
			SaveManager.Utility.DebugLog("Created index", stringListIndex)
			saveTable[stringListIndex] = {}
		end
		saveTable = saveTable[stringListIndex]
	end
	local saveIndex = SaveManager.Utility.GetSaveIndex(ent, getAltSave)
	local data = saveTable[saveIndex]

	if data == nil and initDataIfNotPresent then
		local gameSave = noHourglass and "gameNoBackup" or "game"
		local defaultKey = SaveManager.Utility.GetDefaultSaveKey(ent)
		local defaultSave = SaveManager.DEFAULT_SAVE[gameSave][saveType][defaultKey] or {}
		if ent and type(ent) ~= "number" and ent.Type == EntityType.ENTITY_PICKUP then
			local pickupData = {
				InitSeed = ent.InitSeed,
				RerollSave = SaveManager.Utility.PatchSaveFile({}, defaultSave),
				NoRerollSave = SaveManager.Utility.PatchSaveFile({}, defaultSave)
			}
			saveTable[saveIndex] = pickupData
		else
			saveTable[saveIndex] = SaveManager.Utility.PatchSaveFile({}, defaultSave)
		end
		SaveManager.Utility.DebugLog("Created new", saveType, "data for", saveIndex)
	end
	data = saveTable[saveIndex]

	return data
end

---@param ent? Entity @If an entity is provided, returns an entity specific save within the run save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRunSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, true, "run", nil, allowSoulSave)
end

---@param ent? Entity @If an entity is provided, returns an entity specific save within the run save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table? @Can return nil if data has not been loaded, the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRunSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, false, "run", nil, allowSoulSave)
end

---@param ent? Entity  @If an entity is provided, returns an entity specific save within the floor save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetFloorSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, true, "floor", nil, allowSoulSave)
end

---**NOTE:** If your data is a pickup, use SaveManager.TryGetRerollPickupSave/TryGetNoRerollPickupSave instead
---@param ent? Entity  @If an entity is provided, returns an entity specific save within the floor save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetFloorSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, false, "floor", nil, allowSoulSave)
end

---**NOTE:** If your data is a pickup, use SaveManager.GetRerollPickupSave/NoRerollPickupSave instead
---@param ent? Entity | integer @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRoomSave(ent, noHourglass, listIndex, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, true, "room", listIndex, allowSoulSave)
end

---@param ent? Entity | integer @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRoomSave(ent, noHourglass, listIndex, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, false, "room", listIndex, allowSoulSave)
end

---@param ent? Entity | integer  @If an entity is provided, returns an entity specific save within the room save. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetTempSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, true, "temp", nil, allowSoulSave)
end

---@param ent? Entity | integer  @If an entity is provided, returns an entity specific save within the room save. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetTempSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, false, "temp", nil, allowSoulSave)
end

---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRerollPickupSave(pickup, noHourglass)
	local pickup_save = SaveManager.TryGetRoomSave(pickup, noHourglass)
	if pickup_save then
		return pickup_save.RerollSave
	end
end

---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRerollPickupSave(pickup, noHourglass)
	return SaveManager.GetRoomSave(pickup, noHourglass).RerollSave
end

---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetNoRerollPickupSave(pickup, noHourglass)
	local pickup_save = SaveManager.TryGetRoomSave(pickup, noHourglass)
	if pickup_save then
		return pickup_save.NoRerollSave
	end
end

---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the roomFloor save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? false|boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetNoRerollPickupSave(pickup, noHourglass)
	return SaveManager.GetRoomSave(pickup, noHourglass).NoRerollSave
end

---Returns uniquely-saved data for pickups when outside of the room they're stored in. Indexed by ListIndex
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetOutOfRoomPickupSave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.game.pickupRoom
	end
end

---Please note that this is essentially a normal table with the connotation of being used with UnlockAPI.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetUnlockAPISave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.file.unlockApi
	end
end

---Please note that this is essentially a normal table with the connotation of being used with Dead Sea Scrolls (DSS).
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetDeadSeaScrollsSave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.file.deadSeaScrolls
 	end
end

---This will automatically be filled with save data handled by MinimapAPI
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetMinimapAPISave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.file.minimapAPI
	end
end

---Please note that this is essentially a normal table with the connotation of being used to store settings.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetSettingsSave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.file.settings
	end
end

---Gets the "type" save data within the file save. Basically just a table you can put anything it.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetPersistentSave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.file.other
	end
end

--#endregion

--#region Menu Provider for DSS

local MenuProvider = {}

-- The below functions are all required
---@function
function MenuProvider.SaveSaveData()
	SaveManager.Save()
end

---@function
function MenuProvider.GetPaletteSetting()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenuPalette or nil
end

---@function
function MenuProvider.SavePaletteSetting(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenuPalette = var
end

---@function
function MenuProvider.GetHudOffsetSetting()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	if not REPENTANCE and dssSave then
		return dssSave.HudOffset
	else
		return Options.HUDOffset * 10
	end
end

---@function
function MenuProvider.SaveHudOffsetSetting(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	if not REPENTANCE then
		dssSave.HudOffset = var
	end
end

---@function
function MenuProvider.GetGamepadToggleSetting()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenuControllerToggle or nil
end

---@function
function MenuProvider.SaveGamepadToggleSetting(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenuControllerToggle = var
end

---@function
function MenuProvider.GetMenuKeybindSetting()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenuKeybind or nil
end

---@function
function MenuProvider.SaveMenuKeybindSetting(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenuKeybind = var
end

---@function
function MenuProvider.GetMenuHintSetting()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenuHint or nil
end

---@function
function MenuProvider.SaveMenuHintSetting(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenuHint = var
end

---@function
function MenuProvider.GetMenuBuzzerSetting()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenuBuzzer or nil
end

---@function
function MenuProvider.SaveMenuBuzzerSetting(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenuBuzzer = var
end

---@function
function MenuProvider.GetMenusNotified()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenusNotified or nil
end

---@function
function MenuProvider.SaveMenusNotified(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenusNotified = var
end

---@function
function MenuProvider.GetMenusPoppedUp()
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	return dssSave and dssSave.MenusPoppedUp or nil
end

---@function
function MenuProvider.SaveMenusPoppedUp(var)
	local dssSave = SaveManager.GetDeadSeaScrollsSave()
	dssSave.MenusPoppedUp = var
end

SaveManager.MenuProvider = MenuProvider

--#endregion

return SaveManager
