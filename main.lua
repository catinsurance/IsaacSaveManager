TestMod = RegisterMod("Yor'ue Mother", 1)
TestMod.SaveManager = include("src_test.save_manager")
TestMod.SaveManager.Init(TestMod)

--Tests room-specific data for players, pickups, and slot machines

---@param player EntityPickup
function TestMod:OnPeffectUpdate(player)
	local player_room_save = TestMod.SaveManager.GetRoomSave(player)
	if player_room_save.CountUp then
		if player_room_save.CountUp < 360 then
			player_room_save.CountUp = player_room_save.CountUp + 1
		end
	else
		player_room_save.CountUp = 1
	end
end

TestMod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, TestMod.OnPeffectUpdate)

function TestMod:OnPlayerRender(player)
	local player_room_save = TestMod.SaveManager.TryGetRoomSave(player)
	local renderPos = Isaac.WorldToRenderPosition(player.Position)
	if player_room_save and player_room_save.CountUp then
		Isaac.RenderText(player_room_save.CountUp, renderPos.X, renderPos.Y - 30, 1, 1, 1, 1)
	else
		Isaac.RenderText("N/A", renderPos.X - 10, renderPos.Y - 30, 1, 1, 1, 1)
	end
end

TestMod:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, TestMod.OnPlayerRender)

---@param slot EntitySlot
function TestMod:OnSlotInit(slot)
	local slot_save = TestMod.SaveManager.GetRoomSave(slot)
	slot_save.Encounters = (slot_save.Encounters or 0) + 1
end

TestMod:AddCallback(ModCallbacks.MC_POST_SLOT_INIT, TestMod.OnSlotInit)

---@param slot EntitySlot
function TestMod:OnSlotRender(slot)
	local slot_save = TestMod.SaveManager.GetRoomSave(slot)
	local renderPos = Isaac.WorldToRenderPosition(slot.Position)
	if slot_save and slot_save.Encounters then
		Isaac.RenderText(slot_save.Encounters, renderPos.X, renderPos.Y - 50, 1, 1, 1, 1)
	else
		Isaac.RenderText("N/A", renderPos.X - 10, renderPos.Y - 50, 1, 1, 1, 1)
	end
end

TestMod:AddCallback(ModCallbacks.MC_POST_SLOT_RENDER, TestMod.OnSlotRender)

---@param pickup EntityPickup
function TestMod:OnPickupInit(pickup)
	local pickup_save = TestMod.SaveManager.GetRerollPickupSave(pickup)
	pickup_save.Encounters = (pickup_save.Encounters or 0) + 1
end

TestMod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, TestMod.OnPickupInit)

---@param pickup EntityPickup
function TestMod:OnPickupRender(pickup)
	local pickup_save = TestMod.SaveManager.TryGetRerollPickupSave(pickup)
	local renderPos = Isaac.WorldToRenderPosition(pickup.Position)
	if pickup_save and pickup_save.Encounters then
		Isaac.RenderText(pickup_save.Encounters, renderPos.X, renderPos.Y - 30, 1, 1, 1, 1)
	else
		Isaac.RenderText("N/A", renderPos.X - 10, renderPos.Y - 30, 1, 1, 1, 1)
	end
end

TestMod:AddCallback(ModCallbacks.MC_POST_PICKUP_RENDER, TestMod.OnPickupRender)