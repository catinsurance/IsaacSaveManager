local mod = RegisterMod("Test mod121hkj2h1jk2w", 1)
local saveManager = include("src.save_manager")

saveManager.Init(mod)

-- this code is licensed under a [copyleft](https://en.wikipedia.org/wiki/Copyleft) license: this code is completely okay to modify, copy, redistribute and improve upon, as long as you keep this license notice
-- ↄↄ⃝ Jill "oatmealine" Monoids 2021

local function includes(tab, val)
    for _, v in pairs(tab) do
        if val == v then return true end
    end
    return false
end

local function shallowCopy(tab)
    return {table.unpack(tab)}
end

--- Dump a table to the console
---@param o table @The table to dump
---@param deepDive? boolean @Whether to dump nested tables
---@return string @The dumped table
local function dump(o, deepDive, depth, seen)
    deepDive = deepDive or false
    depth = depth or 0
    seen = seen or {}

    if depth > 50 then return '' end -- prevent infloops

    if type(o) == 'userdata' then -- handle custom isaac types
        if includes(seen, tostring(o)) then return '(circular)' end
        if not getmetatable(o) then return tostring(o) end
        local t = getmetatable(o).__type

        if t == 'Entity' or t == 'EntityBomb' or t == 'EntityEffect' or t == 'EntityFamiliar' or t == 'EntityKnife' or
            t == 'EntityLaser' or t == 'EntityNPC' or t == 'EntityPickup' or t == 'EntityPlayer' or
            t == 'EntityProjectile' or t == 'EntityTear' then
            return t .. ': ' .. (o.Type or '0') .. '.' .. (o.Variant or '0') .. '.' .. (o.SubType or '0')
        elseif t == 'EntityRef' then
            return t .. ' -> ' .. dump(o.Ref, deepDive, depth, seen)
        elseif t == 'EntityPtr' then
            return t .. ' -> ' .. dump(o.Entity, deepDive, depth, seen)
        elseif t == 'GridEntity' or t == 'GridEntityDoor' or t == 'GridEntityPit' or t == 'GridEntityPoop' or
            t == 'GridEntityPressurePlate' or t == 'GridEntityRock' or t == 'GridEntitySpikes' or t == 'GridEntityTNT' then
            return t ..
                ': ' ..
                o:GetType() ..
                '.' .. o:GetVariant() .. '.' .. o.VarData .. ' at ' .. dump(o.Position, deepDive, depth, seen)
        elseif t == 'GridEntityDesc' then
            return t .. ' -> ' .. o.Type .. '.' .. o.Variant .. '.' .. o.VarData
        elseif t == 'Vector' then
            return t .. '(' .. o.X .. ', ' .. o.Y .. ')'
        elseif t == 'Color' then
            return t .. '(' .. o.R .. ', ' .. o.G .. ', ' .. o.B .. ', ' .. o.RO .. ', ' .. o.GO .. ', ' .. o.BO .. ')'
        elseif t == 'Level' then
            return t .. ': ' .. o:GetName()
        elseif t == 'RNG' then
            return t .. ': ' .. o:GetSeed()
        elseif t == 'Sprite' then
            return t ..
                ': ' ..
                o:GetFilename() ..
                ' - ' ..
                (o:IsPlaying(o:GetAnimation()) and 'playing' or 'stopped at') ..
                ' ' .. o:GetAnimation() .. ' f' .. o:GetFrame()
        elseif t == 'TemporaryEffects' then
            local list = o:GetEffectsList()
            local tab = {}
            for i = 0, #list - 1 do
                table.insert(tab, list:Get(i))
            end
            return dump(tab, deepDive, depth, seen)
        else
            local newt = {}
            for k, v in pairs(getmetatable(o)) do
                if type(k) ~= 'userdata' and k:sub(1, 2) ~= '__' then newt[k] = v end
            end

            return 'userdata ' .. dump(newt, deepDive, depth, seen)
        end
    elseif type(o) == 'table' then -- handle tables
        if not deepDive and includes(seen, tostring(o)) then return '(circular)' end
        table.insert(seen, tostring(o))
        local s = '{\n'
        local first = true
        for k, v in pairs(o) do
            if not first then
                s = s .. ',\n'
            end
            s = s .. string.rep('  ', depth + 1)

            if type(k) ~= 'number' then
                table.insert(seen, tostring(v))
                s = s ..
                    dump(k, deepDive, depth + 1, shallowCopy(seen)) ..
                    ' = ' .. dump(v, deepDive, depth + 1, shallowCopy(seen))
            else
                s = s .. dump(v, deepDive, depth + 1, shallowCopy(seen))
            end
            first = false
        end
        if first then return '{}' end
        return s .. '\n' .. string.rep('  ', depth) .. '}'
    elseif type(o) == 'string' then -- anything else resolves pretty easily
        return '"' .. o .. '"'
    else
        return tostring(o)
    end
end


function mod:OnRender()
    local player = Isaac.GetPlayer(0)
    if Input.IsButtonTriggered(Keyboard.KEY_F9, player.ControllerIndex) then
        print(dump(saveManager.GetEntireSave(), true))
    end

    if Input.IsButtonTriggered(Keyboard.KEY_F8, player.ControllerIndex) then
        local data = saveManager.GetRunSave(player)
        data[1] = data
        data[2] = 2
        data[3] = "baz"

        saveManager.Save()
    end
end

mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnRender)