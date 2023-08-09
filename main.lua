
-- This file is for testing purposes.

local mod = RegisterMod("Test mod121hkj2h1jk2w", 1)
local saveManager = include("src.save_manager")
include("unlockapi")
local modName = "Test mod121hkj2h1jk2w"

UnlockAPI.Library:RegisterPlayer(modName, "Gray Isaac")

-- You can edit the default save file either like this or in the save manager itself.
saveManager.Init(mod)

function mod:PreSave(data)
    -- notice how this callback is provided the entire save file
    data.file.unlockApi = UnlockAPI.Library:GetSaveData(modName)
end

saveManager.AddCallback(saveManager.Utility.CustomCallback.PRE_DATA_SAVE, mod.PreSave)

function mod:PostLoad(data)
    -- notice how this callback is provided the entire save file
    UnlockAPI.Library:LoadSaveData(data.file.unlockApi)
end

saveManager.AddCallback(saveManager.Utility.CustomCallback.POST_DATA_LOAD, mod.PostLoad)

-- UnlockAPI wipes data on game start, which is later than the initial load, so load it again in that case.
function mod:PostLoadGameStart()
    local data = saveManager.GetUnlockAPISave()
    if data then
        UnlockAPI.Library:LoadSaveData(data)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.PostLoadGameStart)