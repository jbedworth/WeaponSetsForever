local _, WSF = ...

local FIRST_SLOT = 1
local LAST_SLOT = 19
local EMPTY_SLOT = 0
local IGNORED_SLOT = 1
local MISSING_ITEM = -1
local WEAPON_SLOTS = {
    {name = "MainHandSlot", id = 16},
    {name = "SecondaryHandSlot", id = 17},
    {name = "RangedSlot", id = 18},
}
local REQUIRED_APIS = {
    "CanUseEquipmentSets", "GetEquipmentSetID", "GetEquipmentSetIDs",
    "GetEquipmentSetInfo", "GetNumEquipmentSets", "GetIgnoredSlots",
    "GetItemIDs", "GetItemLocations", "CreateEquipmentSet", "SaveEquipmentSet",
    "IsSlotIgnoredForSave", "IgnoreSlotForSave", "UnignoreSlotForSave",
    "EquipmentSetContainsLockedItems", "UseEquipmentSet",
}
local weapons = {}
local api
local saving = false

function WSF.CheckCapabilities()
    local version, build, _, interface = GetBuildInfo()
    if version ~= "1.60.1" or tostring(build) ~= "70338" or interface ~= 16001 then
        return false, "This test version requires Forever beta 1.60.1 build 70338."
    end
    if type(C_EquipmentSet) ~= "table" then
        return false, "Native equipment sets are unavailable on this client."
    end
    for _, name in ipairs(REQUIRED_APIS) do
        if type(C_EquipmentSet[name]) ~= "function" then
            return false, "Required equipment API is missing: " .. name
        end
    end
    if not C_EquipmentSet.CanUseEquipmentSets() then
        return false, "Native equipment sets are unavailable for this character."
    end
    if type(C_PaperDollInfo) ~= "table"
        or type(C_PaperDollInfo.GetInventorySlotInfo) ~= "function"
        or type(GetInventoryItemID) ~= "function"
        or type(GetInventoryItemTexture) ~= "function"
        or type(IsInventoryItemLocked) ~= "function" then
        return false, "Required inventory APIs are unavailable."
    end
    if EQUIPMENT_SET_EMPTY_SLOT ~= EMPTY_SLOT or EQUIPMENT_SET_IGNORED_SLOT ~= IGNORED_SLOT
        or EQUIPMENT_SET_ITEM_MISSING ~= MISSING_ITEM
        or type(MAX_EQUIPMENT_SETS_PER_PLAYER) ~= "number" then
        return false, "Equipment-set constants do not match the beta source."
    end
    weapons = {}
    for _, slot in ipairs(WEAPON_SLOTS) do
        local id = C_PaperDollInfo.GetInventorySlotInfo(slot.name)
        if id ~= slot.id then
            return false, "Cannot verify weapon slot: " .. slot.name
        end
        weapons[id] = true
    end
    api = C_EquipmentSet
    return true
end

local function Ready()
    if not WSF.available then
        return false, "Weapon sets are unavailable. Check the WSF login message."
    end
    if saving then
        return false, "A weapon set is being saved. Try again after it finishes."
    end
    return true
end

local function ReadSet(id)
    local name = api.GetEquipmentSetInfo(id)
    if not name then
        return nil, "The equipment set no longer exists."
    end
    local ignored = api.GetIgnoredSlots(id)
    local items = api.GetItemIDs(id)
    local locations = api.GetItemLocations(id)
    if type(ignored) ~= "table" or type(items) ~= "table" or type(locations) ~= "table" then
        return nil, "Equipment-set data is unavailable. Try again."
    end
    local verifiedLocations = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        if weapons[slot] then
            if ignored[slot] or locations[slot] == IGNORED_SLOT then
                return nil, "The set does not include every weapon slot. Save it with /wsf save first."
            end
            local location = locations[slot]
            -- Beta tables omit empty slots; require an explicit non-ignored flag.
            if location == nil and ignored[slot] == false and items[slot] == nil then
                location = EMPTY_SLOT
            end
            if type(location) ~= "number" or location < MISSING_ITEM
                or location ~= math.floor(location) then
                return nil, "Weapon-slot data is unavailable. Try again."
            end
            if location > IGNORED_SLOT
                and (type(items[slot]) ~= "number" or items[slot] <= IGNORED_SLOT) then
                return nil, "Weapon item data is unavailable. Try again."
            end
            verifiedLocations[slot] = location
        elseif ignored[slot] ~= true
            or (locations[slot] ~= nil and locations[slot] ~= IGNORED_SLOT) then
            return nil, "The set includes non-weapon gear. Save it with /wsf save first."
        end
    end
    return {id = id, name = name, items = items, locations = verifiedLocations}
end

local function Snapshot()
    local items = {}
    for _, slot in ipairs(WEAPON_SLOTS) do
        if IsInventoryItemLocked(slot.id) then
            return nil, "A weapon slot is locked. Wait for the current item move to finish."
        end
        local item = GetInventoryItemID("player", slot.id)
        if item == nil and GetInventoryItemTexture("player", slot.id) ~= nil then
            return nil, "Weapon item data is unavailable. Try again."
        end
        if item ~= nil and (type(item) ~= "number" or item <= IGNORED_SLOT) then
            return nil, "Weapon item data is invalid. Try again."
        end
        items[slot.id] = item or EMPTY_SLOT
    end
    return items
end

local function ApplySaveFlags(flags)
    for slot = FIRST_SLOT, LAST_SLOT do
        if flags[slot] then
            api.IgnoreSlotForSave(slot)
        else
            api.UnignoreSlotForSave(slot)
        end
    end
end

local function CaptureError(message)
    if type(debugstack) == "function" then
        return tostring(message) .. "\n" .. debugstack(2)
    end
    return message
end

function WSF.Save(name)
    local valid, message = WSF.ValidateName(name)
    if not valid then
        return false, message
    end
    local ready, readyError = Ready()
    if not ready then
        return false, readyError
    end
    if InCombatLockdown() then
        return false, "Cannot save in combat. Wait until combat ends."
    end
    if PaperDollFrame and PaperDollFrame.EquipmentManagerPane
        and PaperDollFrame.EquipmentManagerPane:IsVisible() then
        return false, "Close the Equipment Manager pane before saving."
    end
    local snapshot, snapshotError = Snapshot()
    if not snapshot then
        return false, snapshotError
    end
    local id = api.GetEquipmentSetID(name)
    if id == nil and api.GetNumEquipmentSets() >= MAX_EQUIPMENT_SETS_PER_PLAYER then
        return false, "The native equipment-set limit is reached. Delete an unused set first."
    end

    local previous = {}
    local flags = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        previous[slot] = api.IsSlotIgnoredForSave(slot)
        flags[slot] = not weapons[slot]
    end
    saving = true
    -- The protected region exists only to restore shared flags before rethrowing defects.
    local ran, saved, saveError = xpcall(function()
        ApplySaveFlags(flags)
        if id == nil then
            api.CreateEquipmentSet(name)
            id = api.GetEquipmentSetID(name)
            if id == nil then
                return false, "The client did not create the equipment set."
            end
            -- Creation can synchronously run other AddOns' set-change handlers.
            ApplySaveFlags(flags)
        end
        api.SaveEquipmentSet(id)
        local result, resultError = ReadSet(id)
        if not result or result.name ~= name then
            return false, "The saved set could not be verified. " .. (resultError or "Check the set name.")
        end
        for _, slot in ipairs(WEAPON_SLOTS) do
            local expected = snapshot[slot.id]
            if expected == EMPTY_SLOT then
                if result.locations[slot.id] ~= EMPTY_SLOT then
                    return false, "The saved empty weapon slot could not be verified. Inspect the native set."
                end
            elseif result.items[slot.id] ~= expected
                or result.locations[slot.id] <= IGNORED_SLOT then
                return false, "The saved weapon items could not be verified. Inspect the native set."
            end
        end
        return true
    end, CaptureError)
    local restored, restoreError = xpcall(function()
        ApplySaveFlags(previous)
    end, CaptureError)
    saving = false
    if not restored then
        error(restoreError, 0)
    end
    if not ran then
        error(saved, 0)
    end
    return saved, saveError
end

function WSF.GetWeaponSets()
    local ready, message = Ready()
    if not ready then
        return nil, message
    end
    local result = {}
    for _, id in ipairs(api.GetEquipmentSetIDs()) do
        local entry = ReadSet(id)
        if entry then
            result[#result + 1] = {id = entry.id, name = entry.name}
        end
    end
    table.sort(result, function(left, right)
        return left.name < right.name
    end)
    return result
end

function WSF.PrepareEquip(id)
    local ready, message = Ready()
    if not ready then
        return nil, message
    end
    if InCombatLockdown() then
        return nil, "WSF cannot equip from its UI in combat. Use native /equipset instead."
    end

    if type(id) ~= "number" then
        return nil, "Select a valid weapon set."
    end
    local entry, setError = ReadSet(id)
    if not entry then
        return nil, setError
    end
    for _, slot in ipairs(WEAPON_SLOTS) do
        if entry.locations[slot.id] == MISSING_ITEM then
            return nil, "A saved weapon is unavailable. Put it in your bags and try again."
        end
        if IsInventoryItemLocked(slot.id) then
            return nil, "A weapon slot is locked. Wait for the current item move to finish."
        end
    end
    if api.EquipmentSetContainsLockedItems(id) or UnitCastingInfo("player") then
        return nil, "Items are locked or you are casting. Wait and try again."
    end
    return entry
end
