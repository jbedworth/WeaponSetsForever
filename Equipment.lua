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

local EncodeJSON

local function EncodeString(text)
    -- Escaping | keeps chat from reading it as a UI escape sequence.
    return '"' .. text:gsub('[%c"\\|]', function(character)
        if character == '"' or character == "\\" then
            return "\\" .. character
        end
        return string.format("\\u%04x", character:byte())
    end) .. '"'
end

local function EncodeNumber(number)
    if number ~= number or number == math.huge or number == -math.huge then
        return "null"
    end
    -- %d can overflow a 32-bit C long in Lua 5.1; %.0f is exact for integers below 2^53.
    if number == math.floor(number) and math.abs(number) < 2 ^ 53 then
        return string.format("%.0f", number)
    end
    return string.format("%.17g", number)
end

local function SortKeys(left, right)
    if type(left) == type(right) and (type(left) == "number" or type(left) == "string") then
        return left < right
    end
    return type(left) == "number"
end

-- Equipment slots appear as keys even when absent so sparse native tables stay visible.
local function EncodeSlotTable(source, encodeValue)
    encodeValue = encodeValue or EncodeJSON
    if type(source) ~= "table" then
        return EncodeJSON(source)
    end
    local keys = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        keys[#keys + 1] = slot
    end
    for key in pairs(source) do
        if type(key) ~= "number" or key < FIRST_SLOT or key > LAST_SLOT
            or key ~= math.floor(key) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, SortKeys)
    local fields = {}
    for _, key in ipairs(keys) do
        fields[#fields + 1] = EncodeString(tostring(key)) .. ":" .. encodeValue(source[key])
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

function EncodeJSON(value)
    local kind = type(value)
    if kind == "nil" then
        return "null"
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "number" then
        return EncodeNumber(value)
    elseif kind == "string" then
        return EncodeString(value)
    elseif kind == "table" then
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys, SortKeys)
        local fields = {}
        for _, key in ipairs(keys) do
            fields[#fields + 1] = EncodeString(tostring(key)) .. ":" .. EncodeJSON(value[key])
        end
        return "{" .. table.concat(fields, ",") .. "}"
    end
    return EncodeString(tostring(value))
end

-- Encodes {key, value} pairs in the given order, for readable diagnostics.
local function EncodeFields(pairsList)
    local fields = {}
    for _, field in ipairs(pairsList) do
        fields[#fields + 1] = EncodeString(field[1]) .. ":" .. EncodeJSON(field[2])
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

-- Return order from the pinned EquipmentManagerDocumentation.lua.
local SET_INFO_FIELDS = {
    "name", "iconFileID", "setID", "isEquipped", "numItems",
    "numEquipped", "numInInventory", "numLost", "numIgnored",
}

-- Counts returns with select so trailing nils and undocumented extras stay visible.
local function EncodeSetInfo(...)
    local count = select("#", ...)
    local fields = {}
    for index, field in ipairs(SET_INFO_FIELDS) do
        fields[index] = {field, (select(index, ...))}
    end
    if count > #SET_INFO_FIELDS then
        local extra = {}
        for index = #SET_INFO_FIELDS + 1, count do
            extra[#extra + 1] = EncodeJSON((select(index, ...)))
        end
        return EncodeFields(fields):sub(1, -2)
            .. ',"extraReturns":[' .. table.concat(extra, ",") .. "]}"
    end
    return EncodeFields(fields)
end

-- Packed-location bits from the pinned Blizzard_FrameXMLBase/Constants.lua.
-- Arithmetic replaces bit operations, which plain Lua 5.1 lacks.
local LOCATION_PLAYER = 2 ^ 20 -- ITEM_INVENTORY_LOCATION_PLAYER, 0x00100000
local LOCATION_BAGS = 2 ^ 21 -- ITEM_INVENTORY_LOCATION_BAGS, 0x00200000
local LOCATION_BANK = 2 ^ 22 -- ITEM_INVENTORY_LOCATION_BANK, 0x00400000
local BAG_FACTOR = 2 ^ 8 -- ITEM_INVENTORY_BAG_BIT_OFFSET is 8
local BYTE = 2 ^ 8
local LOCATION_SENTINELS = {
    [MISSING_ITEM] = "missing", [EMPTY_SLOT] = "empty", [IGNORED_SLOT] = "ignored",
}

local function Hex(number)
    local digits = ""
    repeat
        local digit = number % 16
        digits = ("0123456789abcdef"):sub(digit + 1, digit + 1) .. digits
        number = math.floor(number / 16)
    until number == 0
    return "0x" .. digits
end

local function HasFlag(value, flag)
    return math.floor(value / flag) % 2 == 1
end

local function EncodeLocation(location)
    if location == nil then
        return "null"
    end
    if type(location) ~= "number" or location ~= math.floor(location)
        or location < MISSING_ITEM or location >= 2 ^ 53 then
        return EncodeFields({{"kind", "unknown"}})
    end
    if LOCATION_SENTINELS[location] then
        return EncodeFields({{"kind", LOCATION_SENTINELS[location]}})
    end
    local player = HasFlag(location, LOCATION_PLAYER)
    local bags = HasFlag(location, LOCATION_BAGS)
    local bank = HasFlag(location, LOCATION_BANK)
    local slot = location % BYTE
    local bag = math.floor(location / BAG_FACTOR) % BYTE
    local other = location - slot - bag * BAG_FACTOR - (player and LOCATION_PLAYER or 0)
        - (bags and LOCATION_BAGS or 0) - (bank and LOCATION_BANK or 0)
    local kind = bank and "bank" or bags and "bags" or player and "equipped" or "unknown"
    local fields = {
        {"kind", kind}, {"hex", Hex(location)}, {"player", player}, {"bags", bags},
        {"bank", bank}, {"bag", bag}, {"slot", slot},
    }
    if other ~= 0 then
        fields[#fields + 1] = {"otherBits", Hex(other)}
    end
    return EncodeFields(fields)
end

local function EncodeClient()
    local version, build, _, interface = GetBuildInfo()
    return EncodeFields({{"version", version}, {"build", build}, {"interface", interface}})
end

local function EncodeCurrentGear()
    local current = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        current[slot] = GetInventoryItemID("player", slot)
    end
    return EncodeSlotTable(current)
end

local function ProbeByID(id, name)
    local locations = api.GetItemLocations(id)
    return "{" .. table.concat({
        '"client":' .. EncodeClient(),
        '"name":' .. EncodeJSON(name),
        '"id":' .. EncodeJSON(id),
        '"info":' .. EncodeSetInfo(api.GetEquipmentSetInfo(id)),
        '"ignored":' .. EncodeSlotTable(api.GetIgnoredSlots(id)),
        '"locations":' .. EncodeSlotTable(locations),
        '"decodedLocations":' .. EncodeSlotTable(locations, EncodeLocation),
        '"items":' .. EncodeSlotTable(api.GetItemIDs(id)),
        '"current":' .. EncodeCurrentGear(),
    }, ",") .. "}"
end

-- Read-only diagnostic: raw native set tables, unvalidated, plus current gear.
function WSF.ProbeSet(name)
    local ready, message = Ready()
    if not ready then
        return nil, message
    end
    local id = api.GetEquipmentSetID(name)
    if id == nil then
        return nil, "No equipment set is named " .. name .. "."
    end
    return ProbeByID(id, name)
end

-- Returns one probe per set the client reports as equipped. Overlapping
-- weapon-only sets can all be equipped at once. With none, it reports gear only.
function WSF.ProbeEquipped()
    local ready, message = Ready()
    if not ready then
        return nil, message
    end
    local probes = {}
    for _, id in ipairs(api.GetEquipmentSetIDs()) do
        local name, _, _, isEquipped = api.GetEquipmentSetInfo(id)
        if name and isEquipped == true then
            probes[#probes + 1] = ProbeByID(id, name)
        end
    end
    if #probes == 0 then
        probes[1] = '{"client":' .. EncodeClient() .. ',"name":null,"id":null,"current":'
            .. EncodeCurrentGear() .. "}"
    end
    return probes
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
