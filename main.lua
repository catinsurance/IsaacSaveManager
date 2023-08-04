local mod = RegisterMod("Test mod121hkj2h1jk2w", 1)
local saveManager = include("src.save_manager")

-- You can edit the default save file either like this or in the save manager itself.
saveManager.DEFAULT_SAVE.file.other.Test = "Hello world!"
saveManager.Init(mod)

function mod:OnRender()
    local player = Isaac.GetPlayer(0)
    if Input.IsButtonTriggered(Keyboard.KEY_F8, player.ControllerIndex) then
        local runDataWithoutBackup = saveManager.GetRunSave(nil, false)
        local runData = saveManager.GetRunSave()
        if runData and runDataWithoutBackup then -- Check if they're both loaded! (if one is loaded the other is too, but just in case)
            runData.foo = runData.foo and runData.foo + 1 or 1
            runDataWithoutBackup.bar = runDataWithoutBackup.bar and runDataWithoutBackup.bar + 1 or 1
        end
    end

    -- Try this with glowing hourglass!
    if Input.IsButtonTriggered(Keyboard.KEY_F9, player.ControllerIndex) then
        local runDataWithoutBackup = saveManager.GetRunSave(nil, false)
        local runData = saveManager.GetRunSave()
        if runData and runDataWithoutBackup then
            print("Foo in the run save: " .. runData.foo)
            print("Bar in the run save that ignores Glowing Hourglass: " .. runDataWithoutBackup.bar)
        end
    end
end

mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnRender)