---@diagnostic disable: missing-fields
-- Check out everything here: https://github.com/catinsurance/IsaacSaveManager/

local game = Game()
local SaveManager = {}
SaveManager.VERSION = "3.0.0"

if not REPENTOGON or not REPENTANCE_PLUS or not REPENTOGON.MeetsVersion("1.1.1") then
	local msg = "IsaacSaveManager 3.0 and above only supports the latest version of REPENTOGON! Please ensure you have REPENTOGON installed on Repentance+."
	print(msg)
	Isaac.DebugString(msg)
	return
end
SaveManager.Utility = {}

SaveManager.Debug = false

local mFloor = math.floor

--TODO: Look at how REPENTOGON handles serializing and de-serializing
--TODO: Restore room saves for Ascent
--TODO: Restore room saves for Curse of the Maze
--TODO: Testing!

local modReference
local minimapAPIReference
local json = require("json")
local loadedData = false
local dontSaveModData = game:GetFrameCount() == 0
local skipFloorReset = false
local skipRoomReset = false
local currentListIndex = 0
local checkLastIndex = false
local inRunButNotLoaded = true
local isMenuActive = false
local dupeTaggedPickups = {}
local DEBUG_LIST_INDEX = "509"

---@class SaveData
local dataCache = {}

---@type {["0"]: GameSave, ["1"]: GameSave}
local hourglassBackup = {
	["0"] = {},
	["1"] = {}
}

SaveManager.Utility.ERROR_MESSAGE_FORMAT = "[IsaacSaveManager:%s] ERROR: %s (%s)\n"
SaveManager.Utility.WARNING_MESSAGE_FORMAT = "[IsaacSaveManager:%s] WARNING: %s (%s)\n"
SaveManager.Utility.MESSAGE_FORMAT = "[IsaacSaveManager:%s] %s\n"

SaveManager.Utility.ErrorMessages = {
	NOT_INITIALIZED = "The save manager cannot be used without initializing it first!",
	DATA_NOT_LOADED = "An attempt to use save data was made before it was loaded!",
	BAD_DATA = "An attempt to save invalid data was made!",
	BAD_DATA_WARNING = "Data type saved with warning!",
	COPY_ERROR =
	"An error was made when copying from cached data to what would be saved! This could be due to a circular reference.",
	INVALID_ENTITY = "Error using entity \"%s.%s.%s\": The save manager cannot support non-persistent entities!",
	INVALID_ENTITY_WITH_SAVE = "An error was made using entity \"%s.%s.%s\": This entity does not support this save data as it does not persist between floors or move between rooms.",
	INVALID_DEFAULT_WITH_SAVE = "An error was made using entity type \"%s\": This entity does not support this save data as it does not persist between floors or move between rooms."
}
SaveManager.Utility.JsonIncompatibilityType = {
	SPARSE_ARRAY = "Sparse arrays, or arrays with gaps between indexes, will fill gaps with null when encoded. Convert them into strings to avoid this.",
	INVALID_KEY_TYPE = "Error at index \"%s\" with value \"%s\", type \"%s\": Tables that have non-string or non-integer (decimal or non-number) keys cannot be encoded.",
	MIXED_TABLES = "Index \"%s\" with value \"%s\", type \"%s\", found in table with initial type \"%s\": Tables with mixed key types cannot be encoded.",
	NAN_VALUE = "Tables with invalid numbers (NaN, -inf, inf) cannot be encoded.",
	INVALID_VALUE = "Error at index \"%s\" with value \"%s\", type \"%s\": Tables containing anything other than strings, numbers, booleans, or other tables cannot be encoded.",
	CIRCULAR_TABLE = "Tables that contain themselves cannot be encoded.",
}

---@enum SaveCallbacks
SaveManager.SaveCallbacks = {
	---(SaveData saveData): SaveData - Called before validating the save data to store into the mod's save file. This will not run if there happens to be an issue with copying the contents of the save data or its hourglass backup. Return a new table to overwrite the provided save data.
	PRE_DATA_SAVE = "ISAACSAVEMANAGER_PRE_DATA_SAVE",
	---(SaveData saveData) - Called after storing save data into the mod's save file
	POST_DATA_SAVE = "ISAACSAVEMANAGER_POST_DATA_SAVE",
	---(SaveData saveData, boolean isLuamod): SaveData - Called after loading the data from the mod's save file but before loading it into the local save data. Return a new table to overwrite the provided save data. `isLuamod` will return `true` if the mod's data was reloaded via the luamod command
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
	POST_GLOWING_HOURGLASS_RESET = "ISAACSAVEMANAGER_POST_GLOWING_HOURGLASS_RESET",
	---(SaveData saveData): SaveData | boolean - Called after a save data deletion is detected, but before save data is deleted. The Settings save is intentionally not wiped by default. Return `true` to stop deletion, or a new table to overwrite the provided save data.
	PRE_DATA_DELETE = "ISAACSAVEMANAGER_PRE_DATA_DELETE",
	---(SaveData saveData) - Called after a save data deletion is detected and save data is deleted.  The Settings save is intentionally not wiped by default.
	POST_DATA_DELETE = "ISAACSAVEMANAGER_POST_DATA_DELETE"
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
---@field ascent table @Things in this table are persistent throughout the entire run for treasure and boss rooms. Data is removed when the rooms are visited in the Ascent.

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
		ascent = {}
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

function SaveManager.Utility.SendMessage(msg)
	Isaac.ConsoleOutput(SaveManager.Utility.MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg))
	Isaac.DebugString(SaveManager.Utility.MESSAGE_FORMAT:format(modReference and modReference.Name or "???", msg))
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

---@deprecated
function SaveManager.Utility.IsDefaultSaveKey(key)
end

---@deprecated
function SaveManager.Utility.GetDefaultSaveKey(ent)
end

---@param gridIndexOrNil any?
function SaveManager.Utility.GetSaveIndex(gridIndexOrNil)
	if type(gridIndexOrNil) == "number" then
		return "GRID_" .. gridIndexOrNil
	else
		return "GLOBAL"
	end
end

function SaveManager.Utility.GetListIndex()
	--For checking the pre-saved ListIndex on continue
	local roomDesc = game:GetLevel():GetCurrentRoomDesc()
	local listIndex = roomDesc.ListIndex
	local isStartOrContinue = game:IsStartingFromState()
	local shouldCheckLastIndex = checkLastIndex or isStartOrContinue
	if shouldCheckLastIndex then
		listIndex = currentListIndex
	end
	return tostring(listIndex)
end

---@deprecated
function SaveManager.Utility.GetAscentSaveIndex()
end

---Returns a modified version of `deposit` that has the same data that `source` has. Data present in `deposit` but not `source` is unmodified.
---
---Is mostly used with `deposit` as an empty table and `source` the default save data to overrite existing data with the default data.
---@param deposit table
---@param source table
function SaveManager.Utility.PatchSaveFile(deposit, source)
	for i, v in pairs(source) do
		if type(v) == "table" then
			if type(deposit[i]) ~= "table" then
				deposit[i] = {}
			end

			deposit[i] = SaveManager.Utility.PatchSaveFile(deposit[i] ~= nil and deposit[i] or {}, v)
		elseif deposit[i] == nil then
			deposit[i] = v
		end
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

		if type(index) == "number" then
			if mFloor(index) ~= index then
				local valType = type(value) == "userdata" and getmetatable(value).__type or type(value)
				return SaveManager.Utility.ValidityState.INVALID,
					SaveManager.Utility.JsonIncompatibilityType.INVALID_KEY_TYPE:format(index, tostring(value), valType)
			elseif value == math.huge or value == -math.huge or value ~= value then
				return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.NAN_VALUE
			end
		end

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
			--if not SaveManager.Utility.Serialize(tab, index, value) then
				return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.INVALID_VALUE:format(index, tostring(value), valType)
			--end
		end
	end

	-- check for sparse array
	if isSparseArray(tab) then
		hasWarning = SaveManager.Utility.JsonIncompatibilityType.SPARSE_ARRAY
	end

	if SaveManager.Utility.IsCircular(tab) then
		return SaveManager.Utility.ValidityState.INVALID, SaveManager.Utility.JsonIncompatibilityType.CIRCULAR_TABLE
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
---@param ent Entity
---@param saveType DataDuration
---@return boolean, string?
function SaveManager.Utility.IsEntitySaveAllowed(ent, saveType)
	if not SaveManager.Utility.ShouldSaveType(ent.Type, ent.Variant, ent.SubType, ent.SpawnerType, game:GetRoom():IsClear()) then
		return false, SaveManager.Utility.ErrorMessages.INVALID_ENTITY:format(ent.Type)
	end
	local entType = ent.Type
	if entType ~= EntityType.ENTITY_PLAYER
		and entType ~= EntityType.ENTITY_FAMILIAR
		and (entType < 10 or entType == EntityType.ENTITY_EFFECT)
		and (saveType == "run" or saveType == "floor")
	then
		return false, SaveManager.Utility.ErrorMessages.INVALID_ENTITY_WITH_SAVE:format(ent.Type, ent.Variant, ent.SubType)
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
	return level:GetDimension()
end

--#endregion

--#region default data (deprecated)

---IsaacSaveManager 3.0+ no longer supports default data. Please initiate the data manually on SaveManager's POST_GLOBAL_DATA_LOAD or POST_ENTITY_DATA_LOAD
---@deprecated
function SaveManager.Utility.AddDefaultRunData(dataType, data, noHourglass)
end

---IsaacSaveManager 3.0+ no longer supports default data. Please initiate the data manually on SaveManager's POST_GLOBAL_DATA_LOAD or POST_ENTITY_DATA_LOAD
---@deprecated
function SaveManager.Utility.AddDefaultFloorData(dataType, data, noHourglass)
end

---IsaacSaveManager 3.0+ no longer supports default data. Please initiate the data manually on SaveManager's POST_GLOBAL_DATA_LOAD or POST_ENTITY_DATA_LOAD
---@deprecated
function SaveManager.Utility.AddDefaultRoomData()
end

---IsaacSaveManager 3.0+ no longer supports default data. Please initiate the data manually on SaveManager's POST_GLOBAL_DATA_LOAD or POST_ENTITY_DATA_LOAD
---@deprecated
function SaveManager.Utility.AddDefaultTempData(dataType, data, noHourglass)
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

	local newFinalData = SaveManager.Utility.RunCallback(SaveManager.SaveCallbacks.PRE_DATA_SAVE, finalData)
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

	SaveManager.Utility.RunCallback(SaveManager.SaveCallbacks.POST_DATA_SAVE, finalData)
end

local function deleteSave(slot)
	local result = Isaac.RunCallback(SaveManager.SaveCallbacks.PRE_DATA_DELETE, dataCache)
	if result == true then
		return
	elseif type(result) == "table" then
		dataCache = result
	else
		local settingsSave = dataCache.file.settings
		dataCache = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE)
		dataCache.file.settings = settingsSave
	end
	SaveManager.Save()
	local message = "MOD SAVE DATA DELETED!"
	if slot then
		message = "MOD SAVE DATA IN SAVE FILE " ..  slot .. " DELETED!"
	end
	SaveManager.Utility.SendMessage(message)
	Isaac.RunCallback(SaveManager.SaveCallbacks.POST_DATA_DELETE, dataCache)
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

	local newSaveData = SaveManager.Utility.RunCallback(SaveManager.SaveCallbacks.PRE_DATA_LOAD, saveData,
		isLuamod)
	if newSaveData then
		saveData = newSaveData
	end

	if game:GetFrameCount() > 0 then
		currentListIndex = saveData.__SAVEMANAGER_LIST_INDEX or game:GetLevel():GetCurrentRoomDesc().ListIndex
		saveData.__SAVEMANAGER_LIST_INDEX = nil
	end

	dataCache = saveData
	--Would only fail to exist if you continued a run before creating save data for the first time
	if dataCache.hourglassBackup then
		if not dataCache.hourglassBackup["0"] then
			local hourglass_backup = SaveManager.Utility.DeepCopy(dataCache.hourglassBackup)
			hourglassBackup["0"] = hourglass_backup
			hourglassBackup["1"] = hourglass_backup
		else
			hourglassBackup = SaveManager.Utility.DeepCopy(dataCache.hourglassBackup)
		end
	else
		hourglassBackup["0"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		hourglassBackup["1"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
	end

	loadedData = true
	inRunButNotLoaded = false

	SaveManager.Utility.RunCallback(SaveManager.SaveCallbacks.POST_DATA_LOAD, saveData, isLuamod)
end

---@deprecated
function SaveManager.Utility.GetPickupIndex(pickup)
end

---@deprecated
function SaveManager.Utility.GetPickupData(pickup)
end

---Initiates data for pickups that have been duplicated
---@param pickup EntityPickup
local function populateDupePickups(pickup)
	if EntitySaveStateManager.TryGetEntityData(modReference, pickup) then
		return
	end
	local dupedPickup = pickup
	local ptrHash1 = GetPtrHash(dupedPickup)
	--If data already exists,
	dupeTaggedPickups[ptrHash1] = true
	for _, originalPickup in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, dupedPickup.Variant)) do
		local ptrHash2 = GetPtrHash(originalPickup)

		if originalPickup.FrameCount > 0
			and originalPickup.InitSeed == dupedPickup.InitSeed
			and not dupeTaggedPickups[ptrHash2]
		then
			SaveManager.Utility.DebugLog("Identified duplicate InitSeed pickup. Attempting to copy data...")
			dupeTaggedPickups[ptrHash2] = true
			local originalSaveData = EntitySaveStateManager.TryGetEntityData(modReference, originalPickup)
			if originalSaveData then
				local result = Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.DUPE_PICKUP_DATA_LOAD, originalPickup.Variant, originalPickup, dupedPickup, originalSaveData)
				if not result then
					SaveManager.Utility.DebugLog("Duplicate data copied!")
					local pickup_save = EntitySaveStateManager.GetEntityData(modReference, pickup)
					SaveManager.Utility.PatchSaveFile(pickup_save, originalSaveData)
				else
					SaveManager.Utility.DebugLog("Duplicate data prevented from being copied")
				end
			end
			return
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

	checkLastIndex = false

	if not loadedData or inRunButNotLoaded then
		SaveManager.Utility.DebugLog("Game Init")
		onGameLoad()
	end

	if newGame then
		dataCache.game = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		dataCache.gameNoBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup)
		hourglassBackup["0"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		hourglassBackup["1"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
	end

	local listIndex = SaveManager.Utility.GetListIndex()
	local function resetNoRerollData(targetTable, checkIndex)
		if checkIndex and targetTable[listIndex] then
			targetTable = targetTable[listIndex]
		end
		local data = targetTable[defaultSaveIndex]
		if data and ent and data.InitSeed and data.InitSeed ~= ent.InitSeed then
			Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.PRE_PICKUP_INITSEED_MORPH, ent.Variant, ent, data.NoRerollSave)
			if data.InitSeedBackup and ent.InitSeed == data.InitSeedBackup then
				local initSeed = data.InitSeedBackup
				data.InitSeedBackup = data.InitSeed
				data.InitSeed = initSeed
				SaveManager.Utility.DebugLog("Detected flip in", defaultSaveIndex, "! No action taken.")
				return
			end
			data.NoRerollSaveBackup = SaveManager.Utility.DeepCopy(data.NoRerollSave)
			data.InitSeedBackup = data.InitSeed
			data.NoRerollSave = {}
			data.InitSeed = ent.InitSeed
			SaveManager.Utility.DebugLog("Detected init seed change in", defaultSaveIndex,
				"! NoRerollSave has been reset")
			Isaac.RunCallbackWithParam(SaveManager.SaveCallbacks.POST_PICKUP_INITSEED_MORPH, ent.Variant, ent, data.NoRerollSave)
		end
	end
	if ent and ent.Type == EntityType.ENTITY_PICKUP then
		local pickup = ent:ToPickup()
		---@cast pickup EntityPickup
		populateDupePickups(pickup)
		resetNoRerollData(dataCache.game.temp)
		resetNoRerollData(dataCache.game.room, true)
		resetNoRerollData(dataCache.gameNoBackup.temp)
		resetNoRerollData(dataCache.gameNoBackup.room, true)
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
		and not dontSaveModData and Isaac.GetFrameCount() > 0 and Console.GetHistory()[2] == "Success!"
	then
		if game:GetFrameCount() > 0 then
			currentListIndex = game:GetLevel():GetCurrentRoomDesc().ListIndex
		end
		SaveManager.Load(true)
		inRunButNotLoaded = false
	end
end

--#endregion

--#region reset data

---@param saveType string
local function resetData(saveType)
	if (not skipRoomReset and saveType == "temp") or (not skipFloorReset and (saveType == "room" or saveType == "floor")) then
		local typeToCallback = {
			temp = {SaveManager.SaveCallbacks.PRE_TEMP_DATA_RESET, SaveManager.SaveCallbacks.POST_TEMP_DATA_RESET},
			room = {SaveManager.SaveCallbacks.PRE_ROOM_DATA_RESET, SaveManager.SaveCallbacks.POST_ROOM_DATA_RESET},
			floor = {SaveManager.SaveCallbacks.PRE_FLOOR_DATA_RESET, SaveManager.SaveCallbacks.POST_FLOOR_DATA_RESET}
		}
		Isaac.RunCallback(typeToCallback[saveType][1])
		local listIndex = SaveManager.Utility.GetListIndex()

		if saveType == "temp" and listIndex ~= DEBUG_LIST_INDEX then
			--room data from goto commands should be removed, as if it were a temp save. It is not persistent.
			dataCache.game.room[DEBUG_LIST_INDEX] = nil
			dataCache.gameNoBackup.room[DEBUG_LIST_INDEX] = nil
		end
		dataCache.game[saveType] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game[saveType])
		dataCache.gameNoBackup[saveType] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup[saveType])
		SaveManager.Utility.DebugLog("reset", saveType, "data")
		Isaac.RunCallback(typeToCallback[saveType][2])
	end
	if saveType == "temp" then
		skipRoomReset = false
	elseif saveType == "floor" or saveType == "room" then
		skipFloorReset = false
	end
end

local saveFileWait = 3

local function preGameExit(_, shouldSave)
	SaveManager.Utility.DebugLog("pre game exit")

	if not shouldSave then
		dataCache.game = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		dataCache.gameNoBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup)
		hourglassBackup["0"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		hourglassBackup["1"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
	end
	SaveManager.Save()
	if shouldSave then
		dataCache.game = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		dataCache.gameNoBackup = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.gameNoBackup)
		hourglassBackup["0"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
		hourglassBackup["1"] = SaveManager.Utility.PatchSaveFile({}, SaveManager.DEFAULT_SAVE.game)
	end
	inRunButNotLoaded = false
	dontSaveModData = true
	saveFileWait = 0
end

--#endregion

--#region core callbacks

local function postNewRoom()
	SaveManager.Utility.DebugLog("new room")
	local level = game:GetLevel()
	local currentRoomDesc = level:GetCurrentRoomDesc()
	currentListIndex = currentRoomDesc.ListIndex
	if not level:IsAscent() then
		if currentListIndex ~= level:GetCurrentRoomDesc().ListIndex then
			checkLastIndex = true
		end
		local listIndex = tonumber(SaveManager.Utility.GetListIndex())
		---@cast listIndex integer
		local lastRoomType = level:GetRoomByIdx(listIndex).Data.Type
		if lastRoomType ~= RoomType.ROOM_TREASURE and lastRoomType ~= RoomType.ROOM_BOSS then
			SaveManager.Utility.DebugLog("Room at index", listIndex, "is not valid for Ascent")
			checkLastIndex = false
			return
		end
		checkLastIndex = false
	end
	currentListIndex = currentRoomDesc.ListIndex
	resetData("temp")
end

local function postNewLevel()
	SaveManager.Utility.DebugLog("new level")
	resetData("room")
	resetData("floor")
	SaveManager.Save()
end

local function postUpdate()
	dupeTaggedPickups = {}
end

---With REPENTOGON, allows you to load data whenever you select a save slot.
---@param isSlotSelected boolean
local function postSaveSlotLoad(_, slot, isSlotSelected, raw)
	if not isSlotSelected then
		return
	end
	if saveFileWait < 3 then
		saveFileWait = saveFileWait + 1
	else
		if isMenuActive and MenuManager.GetActiveMenu() == MainMenuType.SAVES then
			local sprite = SaveMenu.GetDeletePopupSprite()
			if sprite:GetAnimation() == "DeleteConfirmationIdle"
				and sprite:GetLayerFrameData(8):GetStartFrame() --Cursor
			then
				deleteSave(slot)
				saveFileWait = -2
			end
		end
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
		ModCallbacks.MC_POST_EFFECT_INIT
	}

	for _, initCallback in ipairs(initCallbacks) do
		modReference:AddPriorityCallback(initCallback, SaveManager.Utility.CallbackPriority.IMPORTANT, onEntityInit)
	end

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, SaveManager.Utility.CallbackPriority.EARLY, postUpdate)

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_SLOT_INIT, SaveManager.Utility.CallbackPriority.IMPORTANT,
		onEntityInit)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD,
		SaveManager.Utility.CallbackPriority.IMPORTANT, postSaveSlotLoad)
	modReference:AddPriorityCallback(ModCallbacks.MC_MENU_INPUT_ACTION,
		SaveManager.Utility.CallbackPriority.IMPORTANT, function(_, ent, inputHook, buttonAction)
			isMenuActive = false
			if MenuManager.IsActive and MenuManager.IsActive() == false then
				return
			elseif not MenuManager.IsActive then
				local success, _ = pcall(MenuManager.GetActiveMenu)
				if not success then return end
			end
			isMenuActive = true
			local currentMenu = MenuManager.GetActiveMenu()
			dontSaveModData = currentMenu == MainMenuType.TITLE or
				currentMenu == MainMenuType.MODS
			detectLuamod()
		end)
	modReference:AddCallback(ModCallbacks.MC_POST_GLOWING_HOURGLASS_SAVE, function(_, slot)
		hourglassBackup[tostring(slot)] = SaveManager.Utility.DeepCopy(dataCache.game)
		SaveManager.Utility.DebugLog("Saved hourglass data to slot", slot)
	end)
	modReference:AddCallback(ModCallbacks.MC_PRE_GLOWING_HOURGLASS_LOAD, function(_, slot)
		local slotKey = tostring(slot)
		skipRoomReset = true
		skipFloorReset = true
		Isaac.RunCallback(SaveManager.SaveCallbacks.PRE_GLOWING_HOURGLASS_RESET)
		local newData = SaveManager.Utility.DeepCopy(hourglassBackup[slotKey])
		dataCache.game = SaveManager.Utility.PatchSaveFile(newData, SaveManager.DEFAULT_SAVE.game)
		SaveManager.Utility.DebugLog("Restored data from Glowing Hourglass from slot", slotKey)
		Isaac.RunCallback(SaveManager.SaveCallbacks.POST_GLOWING_HOURGLASS_RESET)
	end)
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

	modReference:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, SaveManager.Utility.CallbackPriority.EARLY,
		postNewRoom)
	modReference:AddPriorityCallback(ModCallbacks.MC_POST_NEW_LEVEL, SaveManager.Utility.CallbackPriority.EARLY,
		postNewLevel)
	modReference:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, SaveManager.Utility.CallbackPriority.LATE,
		preGameExit)

	modReference:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, SaveManager.Utility.CallbackPriority.LATE,
		function()
			SaveManager.Save()
		end,
		CollectibleType.COLLECTIBLE_GENESIS
	)

	-- used to detect if an unloaded mod is this mod for when saving for luamod and for unique per-mod callbacks
	modReference.__SAVEMANAGER_UNIQUE_KEY = ("%s-%s"):format(modReference.Name, Random())

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
	if minimapAPI.BranchVersion == branchVersion then
		minimapAPI.DisableSaving = true
		minimapAPIReference = minimapAPI
		modReference:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, SaveManager.Utility.CallbackPriority.IMPORTANT, function(_, isContinue)
			if modReference:HasData() and MinimapAPI.BranchVersion == branchVersion then
				local minimapSave = SaveManager.GetMinimapAPISave()
				if not minimapSave or not next(minimapSave) then
					dataCache.file.minimapAPI = minimapAPIReference:GetSaveTable(true)
				end
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
---@param noHourglass boolean?
---@param saveType DataDuration
---@param listIndex? integer
---@param allowSoulSave? boolean
---@param initDataIfNotPresent boolean
---@return table
---@overload fun(ent?: Entity | integer, noHourglass: boolean?, saveType: DataDuration, listIndex?: integer, allowSoulSave?: boolean): table?
local function getRespectiveSave(ent, noHourglass, saveType, listIndex, allowSoulSave, initDataIfNotPresent)
	if not SaveManager.Utility.IsDataInitialized(not initDataIfNotPresent) then
		return
	end
	if ent then
		---@diagnostic disable-next-line: param-type-mismatch
		if (type(ent) == "userdata" and not SaveManager.Utility.IsEntitySaveAllowed(ent, saveType)) then
			return
		elseif type(ent) == "integer" and saveType ~= "room" and saveType ~= "temp" then
			return
		end
	end
	noHourglass = noHourglass or false

	---@cast ent integer | nil
	local numberListIndex = listIndex or tonumber(SaveManager.Utility.GetListIndex())
	local stringListIndex = tostring(numberListIndex)

	if type(ent) == "userdata" then
		---@cast ent Entity
		---@diagnostic disable-next-line: undefined-field
		local player = ent and type(ent) == "userdata" and ent:ToPlayer() or nil
		if allowSoulSave
		and player
		and player:GetPlayerType() == PlayerType.PLAYER_THESOUL
		and player:GetSubPlayer() ~= nil
		then
			ent = player:GetSubPlayer()
		end
		local data = EntitySaveStateManager.TryGetEntityData(modReference, ent)
		if initDataIfNotPresent then
			data = EntitySaveStateManager.GetEntityData(modReference, ent)
		end
		--Pickups need their separated Reroll and NoReroll saves.
		if ent:ToPickup() then
			if initDataIfNotPresent then
				data.__SAVEMANAGER_PICKUP_SAVE = {
					InitSeed = ent.InitSeed,
					RerollSave = {},
					NoRerollSave = {}
				}
			end
			return data and data.__SAVEMANAGER_PICKUP_SAVE
			--Need to manually track room-specific data for players and familiars as they're room-persistent.
		elseif (player or ent:ToFamiliar()) and saveType == "room" and data then
			if not data.__SAVEMANAGER_LIST_INDEX_SAVE then
				data.__SAVEMANAGER_LIST_INDEX_SAVE = {[stringListIndex] = {}}
			end
			return data.__SAVEMANAGER_LIST_INDEX_SAVE[stringListIndex]
		end
		return data
	end
	---@type integer?
	local gridIndexOrNil = ent
	local saveTableBackup = dataCache.game[saveType]
	local saveTableNoBackup = dataCache.gameNoBackup[saveType]
	local saveTable = noHourglass and saveTableNoBackup or saveTableBackup
	--Either global or grid index-specific saves from here
	if saveType == "room" then
		if not saveTable[stringListIndex] then
			SaveManager.Utility.DebugLog("Created index", stringListIndex)
			saveTable[stringListIndex] = {}
		end
		saveTable = saveTable[stringListIndex]
	end
	local saveIndex = SaveManager.Utility.GetSaveIndex(gridIndexOrNil)
	local data = saveTable[saveIndex]
	if data == nil and initDataIfNotPresent then
		saveTable[saveIndex] = {}
		SaveManager.Utility.DebugLog("Created new", saveType, "data for", saveIndex)
	end
	data = saveTable[saveIndex]

	return data
end

---Returns a save that lasts the duration of the entire run. Exclusive to players and familiars.
---@param ent? Entity @If an entity is provided, returns an entity specific save within the run save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRunSave(ent, _, allowSoulSave)
	return getRespectiveSave(ent, false, "run", nil, allowSoulSave, true)
end

---Attempts to return a save that lasts the duration of the entire run. Exclusive to players and familiars.
---@param ent? Entity @If an entity is provided, returns an entity specific save within the run save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table? @Can return nil if data has not been loaded, the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRunSave(ent, _, allowSoulSave)
	return getRespectiveSave(ent, false, "run", nil, allowSoulSave)
end

---Returns a save that lasts the duration of the current floor. Exclusive to players and familiars.
---@param ent? Entity  @If an entity is provided, returns an entity specific save within the floor save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetFloorSave(ent, _, allowSoulSave)
	return getRespectiveSave(ent, false, "floor", nil, allowSoulSave, true)
end

---Attempts to return a save that lasts the duration of the current floor. Exclusive to players and familiars.
---@param ent? Entity  @If an entity is provided, returns an entity specific save within the floor save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetFloorSave(ent, _, allowSoulSave)
	return getRespectiveSave(ent, false, "floor", nil, allowSoulSave)
end

---Returns a save that lasts the duration of the current floor, but data is separated per-room.
---**NOTE:** If your data is a pickup, use SaveManager.GetRerollPickupSave/NoRerollPickupSave instead.
---@param ent? Entity | integer @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRoomSave(ent, noHourglass, listIndex, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, "room", listIndex, allowSoulSave, true)
end

---Attempts to return a save that lasts the duration of the current floor, but data is separated per-room.
---**NOTE:** If your data is a pickup, use SaveManager.TryGetRerollPickupSave/TryGetNoRerollPickupSave instead.
---@param ent? Entity | integer @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param listIndex? integer @Returns data for the provided `listIndex` instead of the index of the current room.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRoomSave(ent, noHourglass, listIndex, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, "room", listIndex, allowSoulSave)
end

---Returns a save that lasts the duration of the current room, being reset once you exit the room.
---@param ent? Entity | integer  @If an entity is provided, returns an entity specific save within the room save. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@param allowSoulSave? boolean @If true, if the `ent` is The Soul attached to The Forgotten, will return a differently indexed save, as opposed to a shared save between the two.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetTempSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, "temp", nil, allowSoulSave, true)
end

---Attempts to return a save that lasts the duration of the current room, being reset once you exit the room.
---@param ent? Entity | integer  @If an entity is provided, returns an entity specific save within the room save. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@param noHourglass? boolean @If true, it'll look in a separate game save that is not affected by the Glowing Hourglass.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetTempSave(ent, noHourglass, allowSoulSave)
	return getRespectiveSave(ent, noHourglass, "temp", nil, allowSoulSave)
end

---Returns a save for pickups that persists rerolls, such as through D20 or D6.
---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetRerollPickupSave(pickup)
	return SaveManager.GetRoomSave(pickup).RerollSave
end

---Attempts to return a save for pickups that persists rerolls, such as through D20 or D6.
---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetRerollPickupSave(pickup)
	local pickup_save = SaveManager.TryGetRoomSave(pickup)
	if pickup_save then
		return pickup_save.RerollSave
	end
end

---Returns a save for pickups that does not persist through rerolls, such as through D20 or D6.
---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@return table @Can return nil if data has not been loaded, or the manager has not been initialized. Will create data if none exists.
function SaveManager.GetNoRerollPickupSave(pickup)
	return SaveManager.GetRoomSave(pickup).NoRerollSave
end

---Attempts to return a save for pickups that does not persist through rerolls, such as through D20 or D6.
---@param pickup? EntityPickup @If an entity is provided, returns an entity specific save within the room save, which is a floor-lasting save that has unique data per-room. If a grid index is provided, returns a grid index specific save. Otherwise, returns arbitrary data in the save not attached to an entity.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized, or if no data already existed.
function SaveManager.TryGetNoRerollPickupSave(pickup)
	local pickup_save = SaveManager.TryGetRoomSave(pickup)
	if pickup_save then
		return pickup_save.NoRerollSave
	end
end

---@deprecated
function SaveManager.GetOutOfRoomPickupSave()
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

---Gets the "other" save data within the file save. Can be used for any arbitrary purpose for file-specific saves.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetFileSave()
	if SaveManager.Utility.IsDataInitialized() then
		return dataCache.file.other
	end
end

---Renamed to GetFileSave, but old function kept for legacy.
---
---Gets the "other" save data within the file save. Can be used for any arbitrary purpose for file-specific saves.
---@return table? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetPersistentSave()
	return SaveManager.GetFileSave()
end

---Returns the save table used for Glowing Hourglass backups. It holds two copies, indexed by 0 and 1 for the different hourglass slots provided by the REPENTOGON callbacks.
---
---If not using REPENTOGON, will only ever populate slot 0 instead
---@return {["0"]: table, ["1"]: table}? @Can return nil if data has not been loaded, or the manager has not been initialized.
function SaveManager.GetGlowingHourglassSave()
	if SaveManager.Utility.IsDataInitialized() then
		return hourglassBackup
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
