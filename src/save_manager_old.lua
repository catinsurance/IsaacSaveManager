-- MAKE SURE TO REPLACE ALL INSTANCES OF "YOUR_MOD_REFERENCE" WITH YOUR ACTUAL MOD REFERENCE
-- REPLACE ALL INSTANCES OF "YOUR_MOD_NAME" WITH THE INTERNET NAME OF YOUR MOD `RegisterMod("name", 1)`
-- Made by Slugcat. Report any issues to her.

local json = require("json")
local dataCache = {}
local dataCacheBackup = {}
local shouldRestoreOnUse = false
local loadedData = false
local inRunButNotLoaded = true

local skipNextRoomClear = false
local skipNextLevelClear = false

-- If you want to store default data, you must put it in this table.

function YOUR_MOD_REFERENCE.DefaultSave()
    return {
        --@type RunSave
        run = {
            persistent = {},
            level = {},
            room = {},
        },
        --@type RunSave
        hourglassBackup = {
            persistent = {},
            level = {},
            room = {},
        },
        --@type FileSave
        file = {
            achievements = {},
            dss = {}, -- Dead Sea Scrolls supremacy
            settings = {},
            misc = {},
        },
    }
end


function YOUR_MOD_REFERENCE.DefaultRunSave()
    return {
        persistent = {},
        level = {},
        room = {},
    }
end

function YOUR_MOD_REFERENCE.DeepCopy(tab)
    local copy = {}
    for k, v in pairs(tab) do
        if type(v) == 'table' then
            copy[k] = YOUR_MOD_REFERENCE.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--@return boolean
function YOUR_MOD_REFERENCE.IsDataLoaded()
    return loadedData
end

function YOUR_MOD_REFERENCE.PatchSaveTable(deposit, source)
    source = source or YOUR_MOD_REFERENCE.DefaultSave()

    for i, v in pairs(source) do
        if deposit[i] ~= nil then
            if type(v) == "table" then
                if type(deposit[i]) ~= "table" then
                    deposit[i] = {}
                end

                deposit[i] = YOUR_MOD_REFERENCE.PatchSaveTable(deposit[i], v)
            else
                deposit[i] = v
            end
        else
            if type(v) == "table" then
                if type(deposit[i]) ~= "table" then
                    deposit[i] = {}
                end

                deposit[i] = YOUR_MOD_REFERENCE.PatchSaveTable({}, v)
            else
                deposit[i] = v
            end
        end
    end

    return deposit
end

function YOUR_MOD_REFERENCE.SaveModData()
    if not loadedData then
        return
    end

    -- Save backup
    local backupData = YOUR_MOD_REFERENCE.DeepCopy(dataCacheBackup)
    dataCache.hourglassBackup = YOUR_MOD_REFERENCE.PatchSaveTable(backupData, YOUR_MOD_REFERENCE.DefaultRunSave())

    local finalData = YOUR_MOD_REFERENCE.DeepCopy(dataCache)
    finalData = YOUR_MOD_REFERENCE.PatchSaveTable(finalData, YOUR_MOD_REFERENCE.DefaultSave())

    YOUR_MOD_REFERENCE:SaveData(json.encode(finalData))
end

function YOUR_MOD_REFERENCE.RestoreModData()
    if shouldRestoreOnUse then
        skipNextRoomClear = true
        local newData = YOUR_MOD_REFERENCE.DeepCopy(dataCacheBackup)
        dataCache.run = YOUR_MOD_REFERENCE.PatchSaveTable(newData, YOUR_MOD_REFERENCE.DefaultRunSave())
        dataCache.hourglassBackup = YOUR_MOD_REFERENCE.PatchSaveTable(newData, YOUR_MOD_REFERENCE.DefaultRunSave())
    end
end

function YOUR_MOD_REFERENCE.LoadModData()
    if loadedData then
        return
    end

    local saveData = YOUR_MOD_REFERENCE.DefaultSave()

    if YOUR_MOD_REFERENCE:HasData() then
        local data = json.decode(YOUR_MOD_REFERENCE:LoadData())
        saveData = YOUR_MOD_REFERENCE.PatchSaveTable(data, YOUR_MOD_REFERENCE.DefaultSave())
    end

    dataCache = saveData
    dataCacheBackup = dataCache.hourglassBackup
    loadedData = true
    inRunButNotLoaded = false
end

---@return table?
function YOUR_MOD_REFERENCE.GetRunPersistentSave()
    if not loadedData then
        return
    end

    return dataCache.run.persistent
end

---@return table?
function YOUR_MOD_REFERENCE.GetLevelSave()
    if not loadedData then
        return
    end

    return dataCache.run.level
end

---@return table?
function YOUR_MOD_REFERENCE.GetRoomSave()
    if not loadedData then
        return
    end

    return dataCache.run.room
end

---@return table?
function YOUR_MOD_REFERENCE.GetFileSave()
    if not loadedData then
        return
    end

    return dataCache.file
end

local function ResetRunSave()
    dataCache.run = YOUR_MOD_REFERENCE.DefaultRunSave()
    dataCache.hourglassBackup = YOUR_MOD_REFERENCE.DefaultRunSave()
    dataCacheBackup = YOUR_MOD_REFERENCE.DefaultRunSave()

    YOUR_MOD_REFERENCE.SaveModData()
end

YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_USE_ITEM, YOUR_MOD_REFERENCE.RestoreModData, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)

YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function()
    local newGame = Game():GetFrameCount() == 0

    skipNextLevelClear = true
    skipNextRoomClear = true

    YOUR_MOD_REFERENCE.LoadModData()

    if newGame then
        ResetRunSave()
        shouldRestoreOnUse = false
    end
end)

YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_POST_UPDATE, function ()
    local game = Game()
    if game:GetFrameCount() > 0 then
        if not loadedData and inRunButNotLoaded then
            YOUR_MOD_REFERENCE.LoadModData()
            inRunButNotLoaded = false
            shouldRestoreOnUse = true
        end
    end
end)

--- Replace YOUR_MOD_NAME with the name of your mod, as defined in RegisterMod!
--- This handles the "luamod" command!
YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, mod)
    if mod.Name == "YOUR_MOD_NAME" and Isaac.GetPlayer() ~= nil then
        if loadedData then
            YOUR_MOD_REFERENCE.SaveModData()
        end
    end
end)

YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if not skipNextRoomClear then
        dataCacheBackup.persistent = YOUR_MOD_REFERENCE.DeepCopy(dataCache.run.persistent)
        dataCacheBackup.room = YOUR_MOD_REFERENCE.DeepCopy(dataCache.run.room)
        dataCache.run.room = YOUR_MOD_REFERENCE.DeepCopy(YOUR_MOD_REFERENCE.DefaultRunSave().room)
        YOUR_MOD_REFERENCE.SaveModData()
        shouldRestoreOnUse = true
    end

    skipNextRoomClear = false
end)

YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    if not skipNextLevelClear then
        dataCacheBackup.persistent = YOUR_MOD_REFERENCE.DeepCopy(dataCache.run.persistent)
        dataCacheBackup.level = YOUR_MOD_REFERENCE.DeepCopy(dataCache.run.level)
        dataCache.run.level = YOUR_MOD_REFERENCE.DeepCopy(YOUR_MOD_REFERENCE.DefaultRunSave().level)
        YOUR_MOD_REFERENCE.SaveModData()
        shouldRestoreOnUse = true
    end

    skipNextLevelClear = false
end)

YOUR_MOD_REFERENCE:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    YOUR_MOD_REFERENCE.SaveModData()
    loadedData = false
    inRunButNotLoaded = false
    shouldRestoreOnUse = false
end)