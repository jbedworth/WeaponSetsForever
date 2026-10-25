-- Run from the repository root: lua tests/run.lua
-- These mocks test AddOn logic, not Forever compatibility or protected actions.
-- Every test gets its own globals, native sets, event handlers, and namespace.
if _VERSION ~= "Lua 5.1" then
    io.stderr:write("This suite requires Lua 5.1; found " .. tostring(_VERSION) .. "\n")
    os.exit(1)
end

local tests = {}
local function test(name, body)
    tests[#tests + 1] = {name = name, body = body}
end
local function equal(actual, expected, context)
    if actual ~= expected then
        error((context or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function contains(actual, fragment)
    if type(actual) ~= "string" or not actual:find(fragment, 1, true) then
        error("expected message containing " .. fragment .. ", got " .. tostring(actual), 2)
    end
end
local function copy(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and copy(value) or value
    end
    return result
end
local function same(actual, expected, context)
    if actual == expected then return end
    equal(type(actual), type(expected), context)
    if type(expected) ~= "table" then
        equal(actual, expected, context)
        return
    end
    for key, value in pairs(expected) do
        same(actual[key], value, (context or "table") .. "[" .. tostring(key) .. "]")
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error((context or "table") .. ": unexpected key " .. tostring(key), 2)
        end
    end
end
local function rejected(value, message)
    if value ~= false and value ~= nil then
        error("expected rejection, got " .. tostring(value), 2)
    end
    equal(type(message), "string", "failure message type")
    if message == "" then
        error("failure needs an actionable message", 2)
    end
end
local function raises(body, fragment)
    local ok, message = pcall(body)
    equal(ok, false, "programming defect must propagate")
    contains(tostring(message), fragment)
end
local function weapon(slot)
    return slot == 16 or slot == 17 or slot == 18
end

local function fixture(login)
    local state = {
        gear = {}, textures = {}, locks = {}, flags = {}, sets = {}, order = {},
        frames = {}, timers = {}, messages = {}, calls = {}, now = 0, nextID = 100,
        version = "1.60.1", build = "70450", interface = 16001,
        capable = true, combat = false, managerVisible = false,
        slots = {MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18},
    }
    for slot = 1, 19 do
        state.gear[slot] = 1000 + slot
        state.flags[slot] = slot % 3 == 0
    end
    state.gear[18] = nil
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.SlashCmdList = {}
    env.StaticPopupDialogs = {}
    env.EQUIPMENT_SET_EMPTY_SLOT = 0
    env.EQUIPMENT_SET_IGNORED_SLOT = 1
    env.EQUIPMENT_SET_ITEM_MISSING = -1
    env.MAX_EQUIPMENT_SETS_PER_PLAYER = 10
    env.GetBuildInfo = function()
        return state.version, state.build, "date", state.interface
    end
    -- Like the client, empty slots return no values rather than an explicit nil.
    env.GetInventoryItemID = function(unit, slot)
        equal(unit, "player")
        if state.gear[slot] == nil then return end
        return state.gear[slot]
    end
    env.GetInventoryItemTexture = function(unit, slot)
        equal(unit, "player")
        if state.textures[slot] == nil then return end
        return state.textures[slot]
    end
    env.IsInventoryItemLocked = function(slot) return state.locks[slot] or false end
    env.InCombatLockdown = function() return state.combat end
    env.UnitCastingInfo = function(unit)
        equal(unit, "player")
        return state.casting and "Spell" or nil
    end
    env.IsLoggedIn = function() return false end
    state.toc = {}
    for line in io.lines("WeaponSetsForever.toc") do
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then state.toc[key] = value end
    end
    env.C_AddOns = {GetAddOnMetadata = function(name, field)
        equal(name, "WeaponSetsForever", "metadata uses the AddOn folder name")
        return state.toc[field] or ""
    end}
    env.PaperDollFrame = {EquipmentManagerPane = {
        IsVisible = function() return state.managerVisible end,
        Hide = function() error("AddOn must not hide the native manager") end,
    }}
    env.C_PaperDollInfo = {
        GetInventorySlotInfo = function(name) return state.slots[name] end,
        IsRangedSlotShown = function() return false end,
    }
    env.DEFAULT_CHAT_FRAME = {AddMessage = function(_, message)
        state.messages[#state.messages + 1] = message
    end}
    env.CreateFrame = function(kind)
        equal(kind, "Frame", "minimal event frame")
        local frame = {events = {}, scripts = {}}
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(script, callback) self.scripts[script] = callback end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    function state.emit(event, ...)
        for _, frame in ipairs(state.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    env.C_Timer = {After = function(delay, callback)
        state.timers[#state.timers + 1] = {at = state.now + delay, callback = callback}
    end}
    function state.advance(seconds)
        local target = state.now + seconds
        while true do
            local selected
            for index, timer in ipairs(state.timers) do
                if timer.at <= target and (not selected
                    or timer.at < state.timers[selected].at) then
                    selected = index
                end
            end
            if not selected then break end
            local timer = table.remove(state.timers, selected)
            state.now = timer.at
            timer.callback()
        end
        state.now = target
    end
    local function record(name, ...)
        state.calls[#state.calls + 1] = {name = name, args = {...}}
    end
    function state.count(name)
        local count = 0
        for _, call in ipairs(state.calls) do
            if call.name == name then count = count + 1 end
        end
        return count
    end
    function state.addSet(id, name, fullOutfit)
        local entry = {id = id, name = name, items = {}, locations = {}, ignored = {},
            equipped = false, creator = "Blizzard"}
        for slot = 1, 19 do
            if not fullOutfit and not weapon(slot) then
                entry.ignored[slot] = true
                entry.locations[slot] = 1
            elseif state.gear[slot] then
                entry.items[slot] = state.gear[slot]
                entry.locations[slot] = 2000 + slot
            else
                entry.locations[slot] = 0
            end
        end
        state.sets[id] = entry
        state.order[#state.order + 1] = id
        return entry
    end
    local api = {}
    env.C_EquipmentSet = api
    api.CanUseEquipmentSets = function() return state.capable end
    api.GetEquipmentSetID = function(name)
        for _, id in ipairs(state.order) do
            if state.sets[id] and state.sets[id].name == name then return id end
        end
    end
    api.GetEquipmentSetIDs = function() return copy(state.order) end
    api.GetEquipmentSetInfo = function(id)
        local entry = state.sets[id]
        if entry then return entry.name, "icon", id, entry.equipped end
    end
    api.GetNumEquipmentSets = function() return #state.order end
    api.GetIgnoredSlots = function(id) return state.sets[id].ignored end
    api.GetItemIDs = function(id) return state.sets[id].items end
    api.GetItemLocations = function(id) return state.sets[id].locations end
    api.IsSlotIgnoredForSave = function(slot) return state.flags[slot] end
    api.IgnoreSlotForSave = function(slot)
        record("Ignore", slot)
        state.flags[slot] = true
    end
    api.UnignoreSlotForSave = function(slot)
        record("Unignore", slot)
        state.flags[slot] = false
    end
    api.CreateEquipmentSet = function(name)
        record("Create", name)
        if state.createHook then return state.createHook(name) end
        local id = state.nextID
        state.nextID = id + 1
        state.addSet(id, name)
        state.emit("EQUIPMENT_SETS_CHANGED")
        if state.afterCreate then state.afterCreate(id) end
    end
    api.SaveEquipmentSet = function(id)
        record("Save", id)
        if state.saveHook then return state.saveHook(id) end
        local entry = state.sets[id]
        entry.items, entry.locations, entry.ignored = {}, {}, {}
        for slot = 1, 19 do
            if state.flags[slot] then
                entry.ignored[slot] = true
                entry.locations[slot] = 1
            elseif state.gear[slot] then
                entry.items[slot] = state.gear[slot]
                entry.locations[slot] = 2000 + slot
            else
                entry.locations[slot] = 0
            end
        end
        state.emit("EQUIPMENT_SETS_CHANGED")
        if state.afterSave then state.afterSave(id) end
    end
    api.EquipmentSetContainsLockedItems = function() return state.setLocked or false end
    -- Native equipment effects are explicit test inputs, never inferred from a return value.
    function state.apply(id, onlySlot)
        local entry = state.sets[id]
        for slot = 1, 19 do
            if not entry.ignored[slot] and (not onlySlot or slot == onlySlot) then
                if entry.locations[slot] == 0 then
                    state.gear[slot] = nil
                elseif entry.locations[slot] > 1 then
                    state.gear[slot] = entry.items[slot]
                end
            end
        end
        entry.equipped = onlySlot == nil
    end
    api.UseEquipmentSet = function(id)
        record("Use", id)
        if state.useHook then return state.useHook(id) end
        return true
    end
    -- Login prints a banner, plus a ready hint when available; tests then see
    -- only the messages that follow it.
    state.banner = "WSF: Weapon Sets Forever " .. state.toc.Version .. " by Dyre"
    function state.takeBanner(available)
        equal(state.messages[1], state.banner, "login banner")
        table.remove(state.messages, 1)
        if available then
            contains(state.messages[1], "WSF:   Ready.")
            table.remove(state.messages, 1)
        end
    end
    local namespace = {}
    function state.load(path)
        local chunk, message = loadfile(path)
        if not chunk then error(message, 2) end
        setfenv(chunk, env)
        chunk("WeaponSetsForever", namespace)
    end
    state.env, state.wsf = env, namespace
    state.load("Commands.lua")
    state.load("Equipment.lua")
    state.load("Core.lua")
    if login ~= false then
        state.emit("PLAYER_LOGIN")
        equal(namespace.available, true, "fixture capability gate")
        state.takeBanner(true)
    end
    return state
end

local function noMutation(state, action)
    local gear, sets, flags = copy(state.gear), copy(state.sets), copy(state.flags)
    local calls = #state.calls
    action()
    same(state.gear, gear, "gear")
    same(state.sets, sets, "native sets")
    same(state.flags, flags, "save flags")
    equal(#state.calls, calls, "no mutating API calls")
end
local function assertSnapshot(state, id)
    local entry = state.sets[id]
    for slot = 1, 19 do
        if weapon(slot) then
            equal(entry.ignored[slot], nil, "weapon unignored " .. slot)
            equal(entry.items[slot], state.gear[slot], "sparse item ID " .. slot)
            equal(entry.locations[slot], state.gear[slot] and 2000 + slot or 0,
                "weapon location " .. slot)
        else
            equal(entry.ignored[slot], true, "nonweapon ignored " .. slot)
            equal(entry.locations[slot], 1, "ignored sentinel " .. slot)
            equal(entry.items[slot], nil, "no saved nonweapon item " .. slot)
        end
    end
end
local function equipFixture()
    local state = fixture()
    local entry = state.addSet(7, "Weapons")
    entry.items[16], entry.items[17] = 9001, 9002
    return state, entry
end
local function onlyFailure(state, fragment)
    equal(#state.messages, 1, "single failure report")
    contains(state.messages[1], "WSF: ")
    contains(state.messages[1], fragment)
    if state.messages[1]:find("Equipped weapon set:", 1, true) then
        error("failure must not report success")
    end
end

for _, path in ipairs({"Commands.lua", "Equipment.lua", "Core.lua", "UI.lua"}) do
    local filename = path
    test("Lua 5.1 syntax: " .. filename, function()
        local chunk, message = loadfile(filename)
        equal(type(chunk), "function", message or filename)
        -- In particular, UI.lua is compiled here without executing its globals.
    end)
end

test("fixtures isolate globals, namespace, and character sets", function()
    local left, right = fixture(), fixture()
    equal(left.env.SLASH_WEAPONSETSFOREVER1, "/wsf")
    equal(left.env.SlashCmdList.WEAPONSETSFOREVER, left.wsf.HandleCommand)
    equal(left.wsf.Save("Shared"), true)
    equal(right.wsf.Save("Shared"), true)
    left.sets[100].name = "Changed"
    equal(right.sets[100].name, "Shared")
    equal(rawget(_G, "SLASH_WEAPONSETSFOREVER1"), nil)
end)

local acceptedCommands = {
    {"save Daggers", "Daggers"}, {"SAVE Daggers", "Daggers"},
    {'save "Tank Weapons"', "Tank Weapons"}, {"  save   Daggers  ", "Daggers"},
    {"\tsave\tDaggers\t", "Daggers"}, {'save\t"Tank Weapons"', "Tank Weapons"},
    {'save " A B "', " A B "}, {"save O'Brien", "O'Brien"},
    {"save 1234567890123456", "1234567890123456"},
    {'save "' .. string.rep("\195\169", 16) .. '"', string.rep("\195\169", 16)},
    {"save " .. string.rep("\228\184\173", 16), string.rep("\228\184\173", 16)},
    {"save " .. string.rep("\240\159\152\128", 16), string.rep("\240\159\152\128", 16)},
}
for index, case in ipairs(acceptedCommands) do
    local input, expected = case[1], case[2]
    test("parser accepts case " .. index, function()
        local state = fixture()
        equal(state.wsf.ParseSaveCommand(input), expected)
    end)
end
local invalidCommands = {
    "", " ", "\t", "save", " save \t", 'save ""', 'save "   "',
    "save Tank Weapons", "save Name extra", 'save "Name" extra',
    'save "Name', 'save Name"', 'save "Na"me', 'save Na"me',
    'save "Name""Other"', 'save "Name"Other', 'save "a" "b"',
    'save "a\nb"', 'save "a\rb"', 'save "a\tb"', 'save "a\000b"',
    "save A|B", "save " .. string.rep("a", 17),
    "save " .. string.rep("\195\169", 17),
    "save " .. string.rep("\228\184\173", 17),
    "save " .. string.rep("\240\159\152\128", 17),
    "set Name", "equip Name", "delete Name", "/wsf save Name", "saver Name",
    'save"Name"', "saveName", "save A\tB",
}
for index, input in ipairs(invalidCommands) do
    local message = input
    test("parser rejects case " .. index .. " before mutation", function()
        local state = fixture()
        noMutation(state, function()
            rejected(state.wsf.ParseSaveCommand(message))
            state.wsf.HandleCommand(message)
        end)
        equal(#state.messages, 1)
        contains(state.messages[1], "WSF: ")
    end)
end
for _, value in ipairs({false, 42, {}}) do
    local input = value
    test("parser rejects type " .. type(input), function()
        rejected(fixture().wsf.ParseSaveCommand(input))
    end)
end
test("parser rejects nil", function() rejected(fixture().wsf.ParseSaveCommand(nil)) end)
test("popup name spaces are not command arguments", function()
    equal(fixture().wsf.ValidateName("Tank Weapons"), true)
end)
test("name validation counts spaces within the 16-letter limit", function()
    local wsf = fixture().wsf
    equal(wsf.ValidateName("1234567 12345678"), true)
    rejected(wsf.ValidateName("12345678 12345678"))
end)
test("slash save reports verified success exactly once", function()
    local state = fixture()
    state.env.SlashCmdList.WEAPONSETSFOREVER('save "Tank Weapons"')
    assertSnapshot(state, 100)
    same(state.messages, {"WSF: Saved weapon set: Tank Weapons"})
end)
test("slash save reports core save failure exactly once", function()
    local state = fixture()
    state.combat = true
    noMutation(state, function() state.wsf.HandleCommand("save Weapons") end)
    onlyFailure(state, "combat")
end)

-- Plain /wsf, help, and unknown words print one line naming every command.
local USAGE_LINE = 'WSF: Use /wsf save Name (or /wsf save "Set Name"), /wsf export [Name], '
    .. "/wsf debug_swap [on|off|status], or /wsf help. /weaponsets works the same."
for _, input in ipairs({"", "   ", "help", "HELP", " help ", "help save", "set Weapons",
    "unknown", "saver Name", "/wsf save Name"}) do
    local message = input
    test("usage line for " .. string.format("%q", message), function()
        local state = fixture()
        noMutation(state, function() state.wsf.HandleCommand(message) end)
        same(state.messages, {USAGE_LINE})
    end)
end
test("usage line for a non-string message", function()
    local state = fixture()
    noMutation(state, function() state.wsf.HandleCommand(nil) end)
    same(state.messages, {USAGE_LINE})
end)
test("usage line fits one chat message", function()
    equal(#USAGE_LINE <= 255, true)
end)
test("malformed save keeps the precise save usage", function()
    for _, message in ipairs({"save", "save Tank Weapons", 'save "Name'}) do
        local state = fixture()
        noMutation(state, function() state.wsf.HandleCommand(message) end)
        same(state.messages, {'WSF: Use /wsf save Name or /wsf save "Set Name".'})
    end
    local state = fixture()
    noMutation(state, function() state.wsf.HandleCommand('save "' .. string.rep("a", 17) .. '"') end)
    same(state.messages, {"WSF: Use a set name with at most 16 letters."})
end)
test("/weaponsets runs the same handler as /wsf", function()
    local state = fixture()
    equal(state.env.SLASH_WEAPONSETSFOREVER1, "/wsf")
    equal(state.env.SLASH_WEAPONSETSFOREVER2, "/weaponsets")
    state.env.SlashCmdList.WEAPONSETSFOREVER("save Daggers")
    assertSnapshot(state, 100)
    same(state.messages, {"WSF: Saved weapon set: Daggers"})
end)
test("WSF never registers /wsk, which belongs to WSK", function()
    local state = fixture()
    for key in pairs(state.env.SlashCmdList) do
        for index = 1, 10 do
            local alias = state.env["SLASH_" .. key .. index]
            if type(alias) == "string" then
                equal(alias:lower() ~= "/wsk", true, "WSF must not use /wsk")
            end
        end
    end
end)
local function clashState(aliases)
    local state = fixture(false)
    state.env.SlashCmdList.OTHERADDON = function() end
    for index, alias in ipairs(aliases) do
        state.env["SLASH_OTHERADDON" .. index] = alias
    end
    state.emit("PLAYER_LOGIN")
    state.takeBanner(true)
    return state
end
test("login reports a /wsf clash once and names /weaponsets", function()
    local state = clashState({"/WSF"})
    same(state.messages, {"WSF: Another AddOn (OTHERADDON) also uses /wsf. Use /weaponsets instead."})
end)
test("login reports a /weaponsets clash and names /wsf", function()
    local state = clashState({"/other", "/weaponsets"})
    same(state.messages, {"WSF: Another AddOn (OTHERADDON) also uses /weaponsets. Use /wsf instead."})
end)
test("login reports both clashes without advice", function()
    local state = clashState({"/wsf", "/weaponsets"})
    same(state.messages, {"WSF: Another AddOn (OTHERADDON) also uses /wsf.",
        "WSF: Another AddOn (OTHERADDON) also uses /weaponsets."})
end)
test("login says nothing about /wsk or other commands", function()
    local state = clashState({"/wsk", "/weaponskills", "/wsfx"})
    same(state.messages, {})
end)
test("clash report also runs when WSF is unavailable", function()
    local state = fixture(false)
    state.env.C_EquipmentSet = false
    state.env.SlashCmdList.OTHERADDON = function() end
    state.env.SLASH_OTHERADDON1 = "/wsf"
    state.emit("PLAYER_LOGIN")
    local found = false
    for _, text in ipairs(state.messages) do
        if text == "WSF: Another AddOn (OTHERADDON) also uses /wsf. Use /weaponsets instead." then
            found = true
        end
    end
    equal(found, true, "clash line")
end)

local requiredAPIs = {
    "CanUseEquipmentSets", "GetEquipmentSetID", "GetEquipmentSetIDs",
    "GetEquipmentSetInfo", "GetNumEquipmentSets", "GetIgnoredSlots", "GetItemIDs",
    "GetItemLocations", "CreateEquipmentSet", "SaveEquipmentSet",
    "IsSlotIgnoredForSave", "IgnoreSlotForSave", "UnignoreSlotForSave",
    "EquipmentSetContainsLockedItems", "UseEquipmentSet",
}
local function capabilityFailure(state)
    noMutation(state, function()
        state.emit("PLAYER_LOGIN")
        equal(state.wsf.available, false)
        state.takeBanner(false)
        equal(#state.messages, 1)
        state.emit("PLAYER_LOGIN")
        state.emit("EQUIPMENT_SETS_CHANGED")
        equal(#state.messages, 1, "unsupported capability reported only once")
        rejected(state.wsf.Save("Weapons"))
        rejected(state.wsf.GetWeaponSets())
        rejected(state.wsf.PrepareEquip(7))
    end)
end
for _, name in ipairs(requiredAPIs) do
    local apiName = name
    test("capability rejects missing " .. apiName, function()
        local state = fixture(false)
        state.env.C_EquipmentSet[apiName] = nil
        capabilityFailure(state)
        contains(state.messages[1], apiName)
    end)
end
local invalidCapabilities = {
    {"native table", function(s) s.env.C_EquipmentSet = false end},
    {"paper doll table without the global slot API", function(s) s.env.C_PaperDollInfo = false end},
    {"both slot APIs", function(s) s.env.C_PaperDollInfo.GetInventorySlotInfo = nil end},
    {"global slot API that is not a function", function(s)
        s.env.C_PaperDollInfo = false
        s.env.GetInventorySlotInfo = "MainHandSlot"
    end},
    {"inventory ID", function(s) s.env.GetInventoryItemID = false end},
    {"inventory texture", function(s) s.env.GetInventoryItemTexture = false end},
    {"inventory locks", function(s) s.env.IsInventoryItemLocked = false end},
    {"empty sentinel", function(s) s.env.EQUIPMENT_SET_EMPTY_SLOT = -1 end},
    {"ignored sentinel", function(s) s.env.EQUIPMENT_SET_IGNORED_SLOT = 0 end},
    {"missing sentinel", function(s) s.env.EQUIPMENT_SET_ITEM_MISSING = 1 end},
    {"set limit constant", function(s) s.env.MAX_EQUIPMENT_SETS_PER_PLAYER = false end},
    {"timer table", function(s) s.env.C_Timer = false end},
    {"timer API", function(s) s.env.C_Timer.After = nil end},
}
for _, case in ipairs(invalidCapabilities) do
    local name, change = case[1], case[2]
    test("capability rejects " .. name, function()
        local state = fixture(false)
        change(state)
        capabilityFailure(state)
    end)
end
-- Classic Era and Anniversary have only the global GetInventorySlotInfo,
-- which also returns the texture and a relic flag after the slot ID.
local function classicSlots(state)
    state.env.C_PaperDollInfo = nil
    state.env.GetInventorySlotInfo = function(name)
        local id = state.slots[name]
        if id == nil then error("Invalid inventory slot: " .. tostring(name)) end
        return id, "Interface\Paperdoll\UI-PaperDoll-Slot-" .. name, false
    end
end
test("capability uses the global slot API when C_PaperDollInfo lacks it", function()
    local state = fixture(false)
    classicSlots(state)
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, true)
    state.takeBanner(true)
    equal(#state.messages, 0)
    equal(state.wsf.Save("Classic"), true)
end)
test("capability prefers C_PaperDollInfo over the global slot API", function()
    local state = fixture(false)
    state.env.GetInventorySlotInfo = function() error("global slot API must not be called") end
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, true)
end)
test("capability rejects a wrong slot identity from the global slot API", function()
    local state = fixture(false)
    classicSlots(state)
    state.slots.RangedSlot = 19
    capabilityFailure(state)
    contains(state.messages[1], "RangedSlot")
end)
for _, name in ipairs({"MainHandSlot", "SecondaryHandSlot", "RangedSlot"}) do
    local slotName = name
    test("capability rejects unsupported " .. slotName, function()
        local state = fixture(false)
        state.slots[slotName] = nil
        capabilityFailure(state)
        contains(state.messages[1], slotName)
    end)
    test("capability rejects incorrect identity " .. slotName, function()
        local state = fixture(false)
        state.slots[slotName] = 19
        capabilityFailure(state)
    end)
end
test("login banner shows TOC title, version, and author, then a ready hint", function()
    local state = fixture(false)
    state.emit("PLAYER_LOGIN")
    same(state.messages, {
        "WSF: Weapon Sets Forever " .. state.toc.Version .. " by Dyre",
        "WSF:   Ready. Use the Save and Equip icons in the Character panel, or /wsf save Name.",
    })
    state.emit("PLAYER_LOGIN")
    equal(#state.messages, 2, "banner prints once")
end)
test("login banner precedes the unavailable reason", function()
    local state = fixture(false)
    state.env.C_EquipmentSet = false
    state.emit("PLAYER_LOGIN")
    equal(#state.messages, 2)
    equal(state.messages[1], state.banner)
    contains(state.messages[2], "unavailable on this client")
end)
-- Classic Era: every API is present, but CanUseEquipmentSets can be false
-- while sets still work (WeaponRack never asks). WSF runs with one note.
local SETS_NOTE = "WSF: The game reports equipment sets as unavailable; WSF will try anyway."
    .. " Each save and equip says if it worked."
test("CanUseEquipmentSets false: WSF starts with one note", function()
    local state = fixture(false)
    state.capable = false
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, true)
    state.takeBanner(true)
    same(state.messages, {SETS_NOTE})
    state.emit("PLAYER_LOGIN")
    equal(#state.messages, 1, "note printed once")
end)
test("CanUseEquipmentSets false: save and equip still run and report", function()
    local state = fixture(false)
    state.capable = false
    state.emit("PLAYER_LOGIN")
    state.takeBanner(true)
    state.messages = {}
    equal(state.wsf.Save("Classic"), true)
    assertSnapshot(state, 100)
    equal(state.wsf.Equip(100), true)
end)
test("CanUseEquipmentSets false on a Classic-shaped client still starts", function()
    local state = fixture(false)
    state.capable = false
    state.env.C_PaperDollInfo = nil
    state.env.GetInventorySlotInfo = function(name) return state.slots[name], "texture", false end
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, true)
    state.takeBanner(true)
    same(state.messages, {SETS_NOTE})
end)
test("CanUseEquipmentSets true: no note (Forever unchanged)", function()
    local state = fixture(false)
    state.emit("PLAYER_LOGIN")
    state.takeBanner(true)
    same(state.messages, {})
    equal(state.wsf.equipmentSetsReported, true)
end)
test("debug_swap status shows canUse=false", function()
    local state = fixture(false)
    state.capable = false
    state.emit("PLAYER_LOGIN")
    state.takeBanner(true)
    state.messages = {}
    state.wsf.HandleCommand("debug_swap status")
    contains(state.messages[1], "canUse=false")
end)
test("login banner falls back without the metadata API or fields", function()
    local state = fixture(false)
    state.env.C_AddOns = nil
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, true, "metadata never gates operations")
    equal(state.messages[1], "WSF: Weapon Sets Forever")
    local blank = fixture(false)
    blank.toc = {Title = " "}
    blank.emit("PLAYER_LOGIN")
    equal(blank.messages[1], "WSF: Weapon Sets Forever")
end)
-- Beta builds change several times a week; only missing features disable WSF.
local otherClients = {
    {"next beta build", function(s) s.build = "70500" end},
    {"numeric build", function(s) s.build = 70450 end},
    {"patch version", function(s) s.version = "1.60.2" end},
    {"interface", function(s) s.interface = 16002 end},
    {"string interface", function(s) s.interface = "16001" end},
}
for _, case in ipairs(otherClients) do
    local name, change = case[1], case[2]
    test("capability accepts other client versions: " .. name, function()
        local state = fixture(false)
        change(state)
        state.emit("PLAYER_LOGIN")
        equal(state.wsf.available, true)
        state.takeBanner(true)
        equal(#state.messages, 0)
    end)
end
test("capability accepts numeric beta build and hidden ranged", function()
    local state = fixture(false)
    state.build = 70450
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, true)
end)
test("operations cannot run before PLAYER_LOGIN", function()
    local state = fixture(false)
    noMutation(state, function()
        rejected(state.wsf.Save("Weapons"))
        rejected(state.wsf.GetWeaponSets())
        rejected(state.wsf.PrepareEquip(7))
    end)
end)

test("save creates weapon-only snapshot including hidden empty ranged", function()
    local state = fixture()
    local gear, flags = copy(state.gear), copy(state.flags)
    equal(state.wsf.Save("Weapons"), true)
    equal(state.count("Create"), 1)
    equal(state.count("Save"), 1)
    assertSnapshot(state, 100)
    same(state.gear, gear)
    same(state.flags, flags)
    equal(state.count("Use"), 0)
    equal(#state.messages, 0, "Save does not own feedback")
end)
for _, creator in ipairs({"Blizzard", "OtherAddOn", "WSF"}) do
    local owner = creator
    test("save overwrites full outfit from " .. owner, function()
        local state = fixture()
        local entry = state.addSet(7, "Weapons", true)
        entry.creator = owner
        local gear, flags = copy(state.gear), copy(state.flags)
        equal(state.wsf.Save("Weapons"), true)
        equal(state.count("Create"), 0)
        equal(state.count("Save"), 1)
        equal(#state.order, 1)
        assertSnapshot(state, 7)
        same(state.gear, gear)
        same(state.flags, flags)
        equal(#state.messages, 0)
    end)
end
for _, slot in ipairs({16, 17, 18}) do
    local slotID = slot
    test("save preserves empty supported slot " .. slotID, function()
        local state = fixture()
        state.gear[slotID] = nil
        equal(state.wsf.Save("Empty"), true)
        assertSnapshot(state, 100)
        equal(state.sets[100].locations[slotID], 0)
        equal(state.sets[100].items[slotID], nil)
    end)
end
test("save permits all weapon slots empty", function()
    local state = fixture()
    state.gear[16], state.gear[17], state.gear[18] = nil, nil, nil
    equal(state.wsf.Save("Empty"), true)
    assertSnapshot(state, 100)
end)
test("save keeps duplicate item IDs in distinct slots", function()
    local state = fixture()
    state.gear[16], state.gear[17] = 5555, 5555
    equal(state.wsf.Save("Duplicates"), true)
    assertSnapshot(state, 100)
end)
test("save reapplies flags after synchronous creation event", function()
    local state = fixture()
    local flags = copy(state.flags)
    local frame = state.env.CreateFrame("Frame")
    frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    frame:SetScript("OnEvent", function()
        for slot = 1, 19 do state.flags[slot] = weapon(slot) end
    end)
    equal(state.wsf.Save("Weapons"), true)
    assertSnapshot(state, 100)
    same(state.flags, flags)
end)
test("save blocks synchronous reentrant operations", function()
    local state = fixture()
    state.afterCreate = function()
        rejected(state.wsf.Save("Nested"))
        rejected(state.wsf.GetWeaponSets())
        rejected(state.wsf.PrepareEquip(100))
    end
    equal(state.wsf.Save("Outer"), true)
    equal(state.count("Create"), 1)
    equal(state.count("Save"), 1)
end)
local savePreconditions = {
    {"combat", function(s) s.combat = true end},
    {"visible Equipment Manager", function(s) s.managerVisible = true end},
    {"native set limit", function(s)
        for id = 1, 10 do s.addSet(id, "Set" .. id) end
    end},
}
for _, case in ipairs(savePreconditions) do
    local label, change = case[1], case[2]
    test("save makes no mutation with " .. label, function()
        local state = fixture()
        change(state)
        noMutation(state, function() rejected(state.wsf.Save("New")) end)
        equal(#state.messages, 0)
    end)
end
test("existing set can be overwritten at the native limit", function()
    local state = fixture()
    for id = 1, 10 do state.addSet(id, "Set" .. id, true) end
    equal(state.wsf.Save("Set1"), true)
    equal(state.count("Create"), 0)
    assertSnapshot(state, 1)
end)
for _, name in ipairs({"", " ", "\t", "A|B", "A\nB", string.rep("a", 17)}) do
    local input = name
    test("save rejects invalid name " .. string.format("%q", input), function()
        local state = fixture()
        noMutation(state, function() rejected(state.wsf.Save(input)) end)
    end)
end
test("save rejects nil name before mutation", function()
    local state = fixture()
    noMutation(state, function() rejected(state.wsf.Save(nil)) end)
end)
for _, slot in ipairs({16, 17, 18}) do
    local slotID = slot
    test("save rejects locked slot " .. slotID, function()
        local state = fixture()
        state.locks[slotID] = true
        noMutation(state, function() rejected(state.wsf.Save("Weapons")) end)
    end)
    test("save rejects unavailable item data at slot " .. slotID, function()
        local state = fixture()
        state.gear[slotID] = nil
        state.textures[slotID] = "item texture"
        noMutation(state, function() rejected(state.wsf.Save("Weapons")) end)
    end)
end
for _, item in ipairs({0, 1, -1, "1016"}) do
    local invalid = item
    test("save rejects invalid inventory ID " .. tostring(invalid), function()
        local state = fixture()
        state.gear[16] = invalid
        noMutation(state, function() rejected(state.wsf.Save("Weapons")) end)
    end)
end
local saveFailures = {
    {"creation rejected", function(s) s.createHook = function() return false end end},
    {"save rejected", function(s)
        s.addSet(7, "Weapons", true)
        s.saveHook = function() return false end
    end},
    {"native name truncation", function(s)
        s.afterSave = function(id) s.sets[id].name = "Truncated" end
    end},
    {"item mismatch", function(s)
        s.afterSave = function(id) s.sets[id].items[16] = 9999 end
    end},
    {"occupied slot missing", function(s)
        s.afterSave = function(id) s.sets[id].locations[16] = -1 end
    end},
    {"occupied slot marked empty", function(s)
        s.afterSave = function(id) s.sets[id].locations[16] = 0 end
    end},
    {"empty slot location unavailable", function(s)
        s.afterSave = function(id) s.sets[id].locations[18] = nil end
    end},
    {"empty slot marked missing", function(s)
        s.afterSave = function(id) s.sets[id].locations[18] = -1 end
    end},
    {"weapon ignored", function(s)
        s.afterSave = function(id) s.sets[id].ignored[16] = true end
    end},
    {"nonweapon unignored", function(s)
        s.afterSave = function(id) s.sets[id].ignored[1] = nil end
    end},
    {"item table unavailable", function(s)
        s.afterSave = function(id) s.sets[id].items = nil end
    end},
}
for _, case in ipairs(saveFailures) do
    local label, change = case[1], case[2]
    test("save restores flags after " .. label, function()
        local state = fixture()
        local flags, gear = copy(state.flags), copy(state.gear)
        change(state)
        rejected(state.wsf.Save("Weapons"))
        same(state.flags, flags)
        same(state.gear, gear)
        equal(#state.messages, 0)
        state.createHook, state.saveHook, state.afterSave = nil, nil, nil
        equal(state.wsf.Save("Retry"), true, "save guard released")
    end)
end
for _, phase in ipairs({"create", "save", "read"}) do
    local where = phase
    test("save restores flags and rethrows " .. where .. " defect", function()
        local state = fixture()
        local flags, gear = copy(state.flags), copy(state.gear)
        local original = state.env.C_EquipmentSet.GetItemLocations
        if where == "create" then
            state.createHook = function() error("injected defect") end
        elseif where == "save" then
            state.saveHook = function() error("injected defect") end
        else
            state.env.C_EquipmentSet.GetItemLocations = function() error("injected defect") end
        end
        raises(function() state.wsf.Save("Weapons") end, "injected defect")
        same(state.flags, flags)
        same(state.gear, gear)
        equal(#state.messages, 0)
        state.createHook, state.saveHook = nil, nil
        state.env.C_EquipmentSet.GetItemLocations = original
        equal(state.wsf.Save("Retry"), true)
    end)
end
test("save restores flags after one-shot flag application defect", function()
    local state = fixture()
    local flags = copy(state.flags)
    local original = state.env.C_EquipmentSet.IgnoreSlotForSave
    local injected = false
    state.env.C_EquipmentSet.IgnoreSlotForSave = function(slot)
        if slot == 4 and not injected then
            injected = true
            error("flag defect")
        end
        original(slot)
    end
    raises(function() state.wsf.Save("Weapons") end, "flag defect")
    same(state.flags, flags)
    equal(state.wsf.Save("Retry"), true)
end)
test("save propagates restoration defect and releases save guard", function()
    local state = fixture()
    local original = state.env.C_EquipmentSet.UnignoreSlotForSave
    state.afterSave = function()
        state.env.C_EquipmentSet.UnignoreSlotForSave = function() error("restore defect") end
    end
    raises(function() state.wsf.Save("Weapons") end, "restore defect")
    state.env.C_EquipmentSet.UnignoreSlotForSave = original
    state.afterSave = nil
    equal(state.wsf.Save("Retry"), true)
end)

test("listing is dense, sorted, read-only, and excludes full outfits", function()
    local state = fixture()
    state.addSet(42, "Zulu")
    state.addSet(9, "Armor", true)
    state.addSet(88, "Alpha")
    state.addSet(3, "Middle")
    noMutation(state, function()
        same(state.wsf.GetWeaponSets(), {
            {id = 88, name = "Alpha"}, {id = 3, name = "Middle"}, {id = 42, name = "Zulu"},
        })
    end)
    equal(#state.messages, 0)
end)
test("listing returns an empty dense array", function()
    same(fixture().wsf.GetWeaponSets(), {})
end)
local badSets = {
    {"weapon ignore flag", function(e) e.ignored[16] = true end},
    {"weapon ignored location", function(e) e.locations[17] = 1 end},
    {"weapon missing location data", function(e) e.locations[18] = nil end},
    {"nonweapon ignore flag absent", function(e) e.ignored[1] = nil end},
    {"nonweapon wrong location", function(e) e.locations[19] = 0 end},
    {"ignored table unavailable", function(e) e.ignored = nil end},
    {"item table unavailable", function(e) e.items = nil end},
    {"location table unavailable", function(e) e.locations = nil end},
}
for _, case in ipairs(badSets) do
    local label, change = case[1], case[2]
    test("listing and equip reject " .. label, function()
        local state = fixture()
        change(state.addSet(7, "Bad"))
        state.addSet(8, "Good")
        noMutation(state, function()
            same(state.wsf.GetWeaponSets(), {{id = 8, name = "Good"}})
            rejected(state.wsf.PrepareEquip(7))
        end)
    end)
end
test("missing items stay listed but cannot equip", function()
    local state, entry = equipFixture()
    entry.locations[16] = -1
    same(state.wsf.GetWeaponSets(), {{id = 7, name = "Weapons"}})
    noMutation(state, function() rejected(state.wsf.Equip(7)) end)
    onlyFailure(state, "unavailable")
end)

local equipPreconditions = {
    {"unknown set", function(s) s.sets[7] = nil end},
    {"casting", function(s) s.casting = true end},
    {"native item locks", function(s) s.setLocked = true end},
    {"main hand lock", function(s) s.locks[16] = true end},
    {"off hand lock", function(s) s.locks[17] = true end},
    {"ranged lock", function(s) s.locks[18] = true end},
}
for _, case in ipairs(equipPreconditions) do
    local label, change = case[1], case[2]
    test("equip rejects " .. label .. " before native mutation", function()
        local state = equipFixture()
        change(state)
        noMutation(state, function() rejected(state.wsf.Equip(7)) end)
        equal(#state.messages, 1)
        contains(state.messages[1], "WSF: ")
    end)
end
for _, id in ipairs({"7", false, {}}) do
    local invalid = id
    test("equip rejects ID type " .. type(invalid), function()
        local state = equipFixture()
        noMutation(state, function() rejected(state.wsf.Equip(invalid)) end)
        equal(#state.messages, 1)
    end)
end
test("equip rejects nil ID", function()
    local state = equipFixture()
    noMutation(state, function() rejected(state.wsf.Equip(nil)) end)
end)
test("equip accepts empty locations with sparse item IDs", function()
    local state, entry = equipFixture()
    for _, slot in ipairs({16, 17, 18}) do
        entry.items[slot], entry.locations[slot] = nil, 0
    end
    state.useHook = function(id)
        state.apply(id)
        state.emit("EQUIPMENT_SWAP_FINISHED", true, id)
        return true
    end
    local nonweapons = copy(state.gear)
    equal(state.wsf.Equip(7), true)
    for slot = 1, 19 do
        if weapon(slot) then
            equal(state.gear[slot], nil, "empty weapon slot " .. slot)
        else
            equal(state.gear[slot], nonweapons[slot], "unchanged nonweapon slot " .. slot)
        end
    end
end)
-- Numeric sentinels belong to locations, not to the sparse item-ID table.
test("equip rejects occupied location with unavailable item ID", function()
    local state, entry = equipFixture()
    entry.items[16] = nil
    noMutation(state, function() rejected(state.wsf.Equip(7)) end)
end)
test("equip rejects unknown negative location sentinel", function()
    local state, entry = equipFixture()
    entry.locations[16] = -2
    noMutation(state, function() rejected(state.wsf.Equip(7)) end)
end)
test("equip succeeds from synchronous completion event exactly once", function()
    local state = equipFixture()
    local before = copy(state.gear)
    state.useHook = function(id)
        state.apply(id)
        state.emit("EQUIPMENT_SWAP_FINISHED", true, id)
        return true
    end
    equal(state.wsf.Equip(7), true)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    equal(state.count("Use"), 1)
    for slot = 1, 19 do
        if not weapon(slot) then equal(state.gear[slot], before[slot]) end
    end
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    state.advance(10)
    equal(#state.messages, 1)
end)
test("equip uses verified immediate native state without an event", function()
    local state = equipFixture()
    state.useHook = function(id) state.apply(id) return true end
    equal(state.wsf.Equip(7), true)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    equal(#state.timers, 0)
end)
test("equip does not announce success before asynchronous completion", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true, "native request accepted")
    equal(#state.messages, 0)
    equal(state.count("Use"), 1)
    state.apply(7)
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    state.advance(5)
    equal(#state.messages, 1)
end)
test("equip rejects concurrent request without a second native use", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    rejected(state.wsf.Equip(7))
    equal(state.count("Use"), 1)
    onlyFailure(state, "pending")
    state.apply(7)
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    equal(#state.messages, 2)
end)
test("equip ignores unrelated completion event", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.emit("EQUIPMENT_SWAP_FINISHED", false, 999)
    equal(#state.messages, 0)
    state.apply(7)
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
end)
test("equip handles completion event without optional set ID", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.apply(7)
    state.emit("EQUIPMENT_SWAP_FINISHED", true)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
end)
for _, synchronous in ipairs({true, false}) do
    local sync = synchronous
    test("equip reports partial false event " .. (sync and "sync" or "async"), function()
        local state = equipFixture()
        local before = copy(state.gear)
        if sync then
            state.useHook = function(id)
                state.apply(id, 16)
                state.emit("EQUIPMENT_SWAP_FINISHED", false, id)
                return true
            end
            rejected(state.wsf.Equip(7))
        else
            equal(state.wsf.Equip(7), true)
            state.apply(7, 16)
            state.emit("EQUIPMENT_SWAP_FINISHED", false, 7)
        end
        onlyFailure(state, "Some items may have changed")
        equal(state.gear[16], 9001, "no speculative rollback")
        equal(state.gear[17], before[17])
        equal(state.count("Use"), 1)
        state.advance(10)
        equal(#state.messages, 1)
    end)
end
test("equip rejects false event even when native equipped flag is true", function()
    local state = equipFixture()
    state.useHook = function(id)
        state.apply(id)
        state.emit("EQUIPMENT_SWAP_FINISHED", false, id)
        return true
    end
    rejected(state.wsf.Equip(7))
    onlyFailure(state, "did not complete")
end)
test("true completion event waits for verified state, then the fallback decides", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    equal(#state.messages, 0, "an unverified true result is not yet a failure")
    state.advance(5)
    onlyFailure(state, "did not complete")
end)
test("true event succeeds from weapon slots while isEquipped still lags", function()
    local state, entry = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.apply(7)
    entry.equipped = false
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    state.advance(10)
    equal(#state.messages, 1)
end)
test("true event succeeds for an all-empty set the client never marks equipped", function()
    local state, entry = equipFixture()
    for _, slot in ipairs({16, 17, 18}) do
        entry.items[slot], entry.locations[slot] = nil, 0
    end
    equal(state.wsf.Equip(7), true)
    state.gear[16], state.gear[17] = nil, nil
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
end)
-- Order observed in client traces: true event first, items move afterward.
test("equipment change confirms a swap after the true event, without the fallback", function()
    local state, entry = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    equal(#state.messages, 0)
    state.apply(7, 16)
    entry.equipped = false
    state.emit("PLAYER_EQUIPMENT_CHANGED", 16, true)
    equal(#state.messages, 0, "a partial change is not yet verified")
    state.apply(7)
    entry.equipped = false
    state.emit("PLAYER_EQUIPMENT_CHANGED", 17, true)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    state.emit("PLAYER_EQUIPMENT_CHANGED", 18, true)
    state.advance(10)
    equal(#state.messages, 1, "no duplicate from later changes or the fallback")
    state.useHook = function(id) state.apply(id) return true end
    equal(state.wsf.Equip(7), true, "nothing is left pending")
end)
test("equipment changes without a pending swap are ignored", function()
    local state = equipFixture()
    noMutation(state, function()
        state.emit("PLAYER_EQUIPMENT_CHANGED", 16, true)
    end)
    equal(#state.messages, 0)
end)
test("swap debug reports the equipment-change completion path", function()
    local state, entry = equipFixture()
    state.wsf.SetSwapDebug(true)
    equal(state.wsf.Equip(7), true)
    state.messages = {}
    state.apply(7)
    entry.equipped = false
    state.emit("PLAYER_EQUIPMENT_CHANGED", 16, true)
    equal(state.messages[1], "WSF: Equipped weapon set: Weapons")
    contains(state.messages[2], "via=equipment success=true")
end)
test("fallback succeeds from weapon slots when no event arrives", function()
    local state, entry = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.apply(7)
    entry.equipped = false
    state.advance(5)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
end)
test("partially changed weapons are not verified", function()
    local state, entry = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.apply(7, 16)
    entry.equipped = false
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    equal(#state.messages, 0)
    state.advance(5)
    onlyFailure(state, "Some items may have changed")
end)
for _, outcome in ipairs({false, "nil"}) do
    local result = outcome
    test("equip reports native rejection " .. tostring(result), function()
        local state = equipFixture()
        local before = copy(state.gear)
        state.useHook = function()
            if result == "nil" then return nil end
            return false
        end
        rejected(state.wsf.Equip(7))
        onlyFailure(state, "free bag space")
        same(state.gear, before)
        equal(#state.timers, 0)
    end)
end
test("equip reports full bags through native failure without rollback", function()
    local state = equipFixture()
    state.useHook = function(id)
        state.apply(id, 16)
        state.emit("EQUIPMENT_SWAP_FINISHED", false, id)
        return false
    end
    rejected(state.wsf.Equip(7))
    onlyFailure(state, "free bag space")
    equal(state.count("Use"), 1)
    equal(state.gear[16], 9001)
end)
test("timeout fallback confirms actual native state", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    equal(#state.timers, 1)
    state.advance(4)
    equal(#state.messages, 0)
    state.apply(7)
    state.advance(1)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
end)
test("timeout failure releases pending operation for retry", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.advance(5)
    onlyFailure(state, "did not complete")
    state.useHook = function(id) state.apply(id) return true end
    equal(state.wsf.Equip(7), true)
    equal(state.count("Use"), 2)
    equal(#state.messages, 2)
    contains(state.messages[2], "Equipped weapon set:")
end)
test("old timeout cannot finish a newer pending operation", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.advance(1)
    state.emit("EQUIPMENT_SWAP_FINISHED", false, 7)
    equal(state.wsf.Equip(7), true)
    state.advance(4)
    equal(#state.messages, 1, "old timer ignored")
    state.advance(1)
    equal(#state.messages, 2, "new timer completed")
end)
test("deletion during pending equip reports failure safely", function()
    local state = equipFixture()
    equal(state.wsf.Equip(7), true)
    state.sets[7] = nil
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    state.advance(5)
    onlyFailure(state, "did not complete")
end)
test("native equip defect propagates and permits later retry", function()
    local state = equipFixture()
    state.useHook = function() error("native equip defect") end
    raises(function() state.wsf.Equip(7) end, "native equip defect")
    equal(#state.messages, 0, "do not disguise defects as expected failures")
    state.useHook = function(id) state.apply(id) return true end
    equal(state.wsf.Equip(7), true, "defect must not leave permanent pending state")
end)
for _, transition in ipairs({"two-hand to pair", "pair to two-hand", "shield", "held item", "duplicates"}) do
    local kind = transition
    test("native-only equip transition: " .. kind, function()
        local state, entry = equipFixture()
        if kind == "two-hand to pair" then
            state.gear[16], state.gear[17] = 8000, nil
        elseif kind == "pair to two-hand" then
            entry.items[16], entry.items[17], entry.locations[17] = 8000, nil, 0
        elseif kind == "duplicates" then
            entry.items[16], entry.items[17] = 5555, 5555
        elseif kind == "shield" then
            entry.items[17] = 7001
        else
            entry.items[17] = 7002
        end
        local before = copy(state.gear)
        state.useHook = function(id)
            state.apply(id)
            state.emit("EQUIPMENT_SWAP_FINISHED", true, id)
            return true
        end
        equal(state.wsf.Equip(7), true)
        equal(state.count("Use"), 1)
        equal(state.count("Create"), 0)
        equal(state.count("Save"), 0)
        for slot = 1, 19 do
            if weapon(slot) then
                equal(state.gear[slot], entry.items[slot])
            else
                equal(state.gear[slot], before[slot])
            end
        end
    end)
end

-- Widget attributes and callbacks are mock observations, not client UI verification.
local function uiFixture(options)
    options = options or {}
    local state = fixture(false)
    local env = state.env
    state.widgets = {}
    env.UISpecialFrames = {}
    env.StaticPopup_Show = function() error("custom dialogs must not use StaticPopup") end
    local function widget(kind, name, parent, template)
        local object = {kind = kind, name = name, parent = parent, template = template,
            events = {}, scripts = {}, points = {}, children = {}, textures = {},
            labels = {}, shown = true, enabled = true, focus = false, text = ""}
        state.widgets[#state.widgets + 1] = object
        if parent then parent.children[#parent.children + 1] = object end
        if name then
            contains(name, "WeaponSetsForever")
            env[name] = object
        end
        function object:RegisterEvent(event) self.events[event] = true end
        function object:UnregisterEvent(event) self.events[event] = nil end
        function object:SetScript(script, callback) self.scripts[script] = callback end
        function object:GetScript(script) return self.scripts[script] end
        function object:GetName() return self.name end
        function object:GetParent() return self.parent end
        function object:IsShown() return self.shown end
        function object:IsVisible()
            return self.shown and (not self.parent or self.parent:IsVisible())
        end
        local function visibility(self, shown)
            local before = {}
            for _, item in ipairs(state.widgets) do before[item] = item:IsVisible() end
            self.shown = shown
            for _, item in ipairs(state.widgets) do
                local visible = item:IsVisible()
                if visible ~= before[item] then
                    local script = item.scripts[visible and "OnShow" or "OnHide"]
                    if script then script(item) end
                end
            end
        end
        function object:Show() visibility(self, true) end
        function object:Hide() visibility(self, false) end
        function object:SetSize(width, height) self.width, self.height = width, height end
        function object:SetWidth(width) self.width = width end
        function object:SetHeight(height) self.height = height end
        function object:SetPoint(...) self.points[#self.points + 1] = {...} end
        function object:SetAllPoints(...) self.allPoints = {...} end
        function object:SetFrameStrata(strata) self.strata = strata end
        function object:EnableMouse(value) self.mouseEnabled = value end
        function object:SetText(text) self.text = text end
        function object:GetText() return self.text end
        function object:SetEnabled(value) self.enabled = value end
        function object:IsEnabled() return self.enabled end
        function object:SetFontObject(font) self.font = font end
        function object:SetTextColor(...) self.textColor = {...} end
        function object:SetJustifyH(value) self.justify = value end
        function object:SetAutoFocus(value) self.autoFocus = value end
        function object:SetFocus() self.focus = true end
        function object:ClearFocus() self.focus = false end
        function object:SetColorTexture(...) self.color = {...} end
        function object:SetTexture(path) self.texturePath = path end
        function object:SetDesaturated(value) self.desaturated = value end
        function object:SetHighlightTexture(path, mode) self.highlight = {path, mode} end
        function object:CreateTexture(name, layer)
            local texture = widget("Texture", name, self)
            texture.layer = layer
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function object:CreateFontString(name, layer, font)
            local label = widget("FontString", name, self, font)
            label.layer = layer
            self.labels[#self.labels + 1] = label
            return label
        end
        return object
    end
    env.CreateFrame = function(kind, name, parent, template)
        local frame = widget(kind, name, parent, template)
        state.frames[#state.frames + 1] = frame
        return frame
    end
    env.CharacterFrame = widget("Frame")
    local manager = env.PaperDollFrame.EquipmentManagerPane
    env.PaperDollFrame = widget("Frame", nil, env.CharacterFrame)
    local items
    if options.classic then
        -- Classic Era and Anniversary: a global items frame, no LeftPaneHost,
        -- and no native Equipment Manager pane.
        items = widget("Frame", nil, env.PaperDollFrame)
        if not options.noItemsFrame then env.PaperDollItemsFrame = items end
    else
        env.CharacterFrame.LeftPaneHost = widget("Frame", nil, env.CharacterFrame)
        env.PaperDollFrame.EquipmentManagerPane = manager
        items = widget("Frame", nil, env.PaperDollFrame)
        env.PaperDollFrame.ItemsFrame = items
    end
    state.itemsFrame = items
    if not options.missingSlots then
        env.CharacterWristSlot = widget("ItemButton", nil, items)
        env.CharacterTrinket1Slot = widget("ItemButton", nil, items)
    end
    env.GameTooltip = widget("Tooltip")
    env.GameTooltip:Hide()
    function env.GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function env.GameTooltip:SetText(text) self.text, self.lines = text, {} end
    function env.GameTooltip:AddLine(...) self.lines[#self.lines + 1] = {...} end
    function state.fire(object, script, ...)
        local callback = object:GetScript(script)
        equal(type(callback), "function", script)
        return callback(object, ...)
    end
    function state.button(parent, text)
        for _, child in ipairs(parent.children) do
            if child.kind == "Button" and child.text == text then return child end
        end
        error("missing mock button: " .. text)
    end
    function state.escape()
        for _, name in ipairs(env.UISpecialFrames) do
            local frame = env[name]
            if frame and frame:IsShown() then frame:Hide() end
        end
    end
    if options.missingTimer then env.C_Timer = nil end
    state.load("UI.lua")
    if options.uiFirst then
        local core, ui = state.frames[1], state.frames[2]
        state.frames[1], state.frames[2] = ui, core
    end
    state.emit("PLAYER_LOGIN")
    state.advance(0)
    state.takeBanner(state.wsf.available)
    if options.missingSlots or options.noItemsFrame then return state end
    state.saveDialog = env.WeaponSetsForeverSaveDialog
    state.equipDialog = env.WeaponSetsForeverEquipDialog
    equal(type(state.saveDialog), "table", "named save dialog")
    equal(type(state.equipDialog), "table", "named equip dialog")
    state.controls = state.saveDialog:GetParent()
    state.saveButton = state.controls.save
    state.equipButton = state.controls.equip
    same(env.StaticPopupDialogs, {}, "no StaticPopup registration")
    return state
end
local function savePrompt()
    local state = uiFixture()
    state.fire(state.saveButton, "OnClick")
    local dialog = state.saveDialog
    equal(dialog:IsShown(), true)
    equal(dialog.editBox.focus, true)
    dialog.editBox:SetText("Tank Weapons")
    return state, dialog, dialog.editBox
end
test("custom save dialog accepts literal multi-word name without quotes", function()
    local state, dialog = savePrompt()
    state.fire(dialog.saveButton, "OnClick")
    equal(state.sets[100].name, "Tank Weapons")
    same(state.messages, {"WSF: Saved weapon set: Tank Weapons"})
    equal(dialog:IsShown(), false)
end)
test("custom save dialog Enter saves once and closes", function()
    local state, dialog, edit = savePrompt()
    state.fire(edit, "OnEnterPressed")
    state.fire(edit, "OnEnterPressed")
    state.fire(dialog.saveButton, "OnClick")
    equal(dialog:IsShown(), false)
    equal(edit.focus, false)
    equal(state.count("Save"), 1)
    equal(#state.messages, 1)
end)
for _, reason in ipairs({"combat", "manager", "unavailable", "empty", "save failure"}) do
    local guard = reason
    test("custom save dialog retains input and focus after " .. guard, function()
        local state, dialog, edit = savePrompt()
        if guard == "combat" then state.combat = true
        elseif guard == "manager" then state.managerVisible = true
        elseif guard == "unavailable" then state.wsf.available = false
        elseif guard == "empty" then edit:SetText("   ")
        else state.locks[16] = true end
        local original = edit:GetText()
        edit:ClearFocus()
        noMutation(state, function() state.fire(dialog.saveButton, "OnClick") end)
        equal(dialog:IsShown(), true)
        equal(edit:GetText(), original)
        equal(edit.focus, true)
        equal(#state.messages, 1)
    end)
end
test("custom save dialog resets on show and clears focus on Escape", function()
    local state, dialog, edit = savePrompt()
    state.fire(edit, "OnEscapePressed")
    equal(dialog:IsShown(), false)
    equal(edit.focus, false)
    state.fire(state.saveButton, "OnClick")
    equal(edit:GetText(), "")
    equal(edit.focus, true)
    state.escape()
    equal(dialog:IsShown(), false)
    equal(edit.focus, false)
    equal(state.count("Save"), 0)
end)

local COMBAT_EQUIP_MESSAGE = "WSF cannot equip from its UI in combat. Use native /equipset instead."
local function combatEquipFailure(state)
    onlyFailure(state, COMBAT_EQUIP_MESSAGE)
    equal(state.messages[1], "WSF: " .. COMBAT_EQUIP_MESSAGE)
    equal(state.messages[1]:find("bag space", 1, true), nil)
    equal(state.messages[1]:find("Some items may have changed", 1, true), nil)
    equal(state.count("Use"), 0, "combat must not call UseEquipmentSet")
    equal(#state.timers, 0, "rejected equip must not schedule work")
end
local function rejectCombatEquip(state, id)
    noMutation(state, function()
        local entry, message = state.wsf.PrepareEquip(id)
        equal(entry, nil)
        equal(message, COMBAT_EQUIP_MESSAGE)
        equal(#state.messages, 0, "PrepareEquip does not report")
        local success, equipError = state.wsf.Equip(id)
        equal(success, false)
        equal(equipError, COMBAT_EQUIP_MESSAGE)
    end)
    combatEquipFailure(state)
end
test("direct equip and preparation reject combat without native calls or queued work", function()
    local state = equipFixture()
    state.combat = true
    state.useHook = function() error("combat must not reach native equip") end
    rejectCombatEquip(state, 7)
    noMutation(state, function()
        state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
        state.advance(10)
        state.combat = false
        state.emit("PLAYER_REGEN_ENABLED")
        state.advance(10)
    end)
    combatEquipFailure(state)
    state.useHook = nil
    equal(state.wsf.Equip(7), true, "explicit retry works after combat")
    equal(state.count("Use"), 1)
end)
test("combat guard does not read set data or item locks", function()
    local state = equipFixture()
    state.combat = true
    local function unexpected() error("combat guard must run before set and lock reads") end
    for _, name in ipairs({"GetEquipmentSetInfo", "GetIgnoredSlots", "GetItemIDs",
        "GetItemLocations", "EquipmentSetContainsLockedItems"}) do
        state.env.C_EquipmentSet[name] = unexpected
    end
    state.env.IsInventoryItemLocked = unexpected
    state.env.UnitCastingInfo = unexpected
    rejectCombatEquip(state, 7)
end)
test("readiness failure precedes combat rejection", function()
    local state = equipFixture()
    state.combat = true
    state.wsf.available = false
    noMutation(state, function()
        local entry, message = state.wsf.PrepareEquip(7)
        equal(entry, nil)
        contains(message, "unavailable")
        equal(#state.messages, 0)
        local success, equipError = state.wsf.Equip(7)
        equal(success, false)
        equal(equipError, message)
    end)
    onlyFailure(state, "unavailable")
    equal(state.count("Use"), 0)
    equal(#state.timers, 0)
end)
for _, slot in ipairs({16, 17, 18}) do
    local slotID = slot
    test("combat guard precedes missing saved weapon " .. slotID, function()
        local state, entry = equipFixture()
        state.combat = true
        entry.locations[slotID] = -1
        rejectCombatEquip(state, 7)
    end)
end
for _, case in ipairs(equipPreconditions) do
    local label, change = case[1], case[2]
    test("combat guard precedes equip precondition: " .. label, function()
        local state = equipFixture()
        state.combat = true
        change(state)
        rejectCombatEquip(state, 7)
    end)
end
for _, case in ipairs(badSets) do
    local label, change = case[1], case[2]
    test("combat guard precedes set validation: " .. label, function()
        local state, entry = equipFixture()
        state.combat = true
        change(entry)
        rejectCombatEquip(state, 7)
    end)
end
for _, id in ipairs({"7", false, {}}) do
    local invalid = id
    test("combat guard precedes ID validation: " .. type(invalid), function()
        local state = equipFixture()
        state.combat = true
        rejectCombatEquip(state, invalid)
    end)
end
test("combat guard precedes nil ID validation", function()
    local state = equipFixture()
    state.combat = true
    rejectCombatEquip(state, nil)
end)
for _, slot in ipairs({16, 17, 18}) do
    local slotID = slot
    test("out-of-combat equip rejects missing saved weapon " .. slotID, function()
        local state, entry = equipFixture()
        equal(state.combat, false)
        entry.locations[slotID] = -1
        noMutation(state, function() rejected(state.wsf.Equip(7)) end)
        onlyFailure(state, "unavailable")
    end)
end
for _, result in ipairs({false, "nil", "partial"}) do
    local outcome = result
    test("out-of-combat equip preserves native failure: " .. tostring(outcome), function()
        local state = equipFixture()
        equal(state.combat, false)
        local before = copy(state.gear)
        state.useHook = function(id)
            if outcome == "partial" then
                state.apply(id, 16)
                state.emit("EQUIPMENT_SWAP_FINISHED", false, id)
            elseif outcome == "nil" then
                return nil
            end
            return false
        end
        rejected(state.wsf.Equip(7))
        onlyFailure(state, "Some items may have changed")
        equal(state.count("Use"), 1)
        if outcome == "partial" then
            equal(state.gear[16], 9001, "no unverified rollback")
            before[16] = 9001
        end
        same(state.gear, before)
        state.emit("EQUIPMENT_SWAP_FINISHED", false, 7)
        state.advance(10)
        equal(#state.messages, 1)
    end)
end
for _, reason in ipairs({"combat", "manager", "unavailable"}) do
    local guard = reason
    test("save dialog blocks opening when " .. guard, function()
        local state = uiFixture()
        if guard == "combat" then state.combat = true
        elseif guard == "manager" then state.managerVisible = true
        else state.wsf.available = false end
        noMutation(state, function() state.fire(state.saveButton, "OnClick") end)
        equal(state.saveDialog:IsShown(), false)
        equal(#state.messages, 1)
        contains(state.messages[1], guard == "manager" and "Close the Equipment Manager"
            or guard == "combat" and "combat" or "unavailable")
    end)
end
for _, reason in ipairs({"combat", "manager"}) do
    local guard = reason
    test("save button rechecks " .. guard .. " on acceptance", function()
        local state, dialog, edit = savePrompt()
        if guard == "combat" then state.combat = true else state.managerVisible = true end
        noMutation(state, function() state.fire(dialog.saveButton, "OnClick") end)
        equal(dialog:IsShown(), true)
        equal(edit:GetText(), "Tank Weapons")
        equal(edit.focus, true)
        equal(#state.messages, 1)
        contains(state.messages[1], guard == "combat" and "combat" or "Close the Equipment Manager")
    end)
end
test("entering combat closes only save dialog and clears focus", function()
    local state, dialog, edit = savePrompt()
    state.combat = true
    state.emit("PLAYER_REGEN_DISABLED")
    equal(dialog:IsShown(), false)
    equal(edit.focus, false)
    onlyFailure(state, "cannot be saved in combat")
    state.emit("PLAYER_REGEN_DISABLED")
    equal(#state.messages, 1, "no repeated close feedback")
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    equal(state.equipDialog:IsShown(), true, "equip opens in combat")
    state.emit("PLAYER_REGEN_DISABLED")
    equal(state.equipDialog:IsShown(), true, "combat leaves equip list open")
    equal(#state.messages, 1)
    equal(state.count("Save"), 0)
end)
for _, combat in ipairs({false, true}) do
    local inCombat = combat
    test("equip row calls core directly " .. (inCombat and "in combat" or "out of combat"), function()
        local state = uiFixture()
        -- Different weapons, so the swap is not already verified when it starts.
        local entry = state.addSet(7, "Weapons")
        entry.items[16], entry.items[17] = 9001, 9002
        state.combat = inCombat
        state.managerVisible = true
        state.fire(state.equipButton, "OnClick")
        local row = state.button(state.equipDialog, "Weapons")
        local original, calls = state.wsf.Equip, 0
        state.wsf.Equip = function(id)
            calls = calls + 1
            equal(id, 7)
            return original(id)
        end
        if inCombat then
            noMutation(state, function() state.fire(row, "OnClick") end)
            equal(calls, 1)
            combatEquipFailure(state)
            equal(state.equipDialog:IsShown(), true)
            equal(row.setID, 7)
            equal(row.setName, "Weapons")
            noMutation(state, function()
                state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
                state.advance(10)
                state.combat = false
                state.emit("PLAYER_REGEN_ENABLED")
                state.advance(10)
            end)
            combatEquipFailure(state)
            equal(state.equipDialog:IsShown(), true)
            equal(calls, 1, "no deferred row equip")
            return
        end
        state.fire(row, "OnClick")
        equal(calls, 1)
        equal(state.count("Use"), 1)
        equal(state.equipDialog:IsShown(), false)
        equal(row.setID, nil)
        equal(#state.messages, 0, "UI does not report accepted request as completion")
        state.apply(7)
        state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
        state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
        state.advance(5)
        same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    end)
end
for _, outcome in ipairs({"native rejection", "synchronous success", "synchronous failure", "locked", "missing"}) do
    local result = outcome
    test("equip row adds no duplicate feedback: " .. result, function()
        local state = uiFixture()
        local entry = state.addSet(7, "Weapons")
        equal(state.combat, false)
        if result == "locked" then state.locks[16] = true
        elseif result == "missing" then entry.locations[17] = -1
        else
            state.useHook = function(id)
                if result == "native rejection" then return false end
                state.apply(id, result == "synchronous failure" and 16 or nil)
                state.emit("EQUIPMENT_SWAP_FINISHED", result == "synchronous success", id)
                return true
            end
        end
        state.fire(state.equipButton, "OnClick")
        local row = state.button(state.equipDialog, "Weapons")
        state.fire(row, "OnClick")
        equal(#state.messages, 1)
        local success = result == "synchronous success"
        equal(state.equipDialog:IsShown(), not success)
        contains(state.messages[1], success and "Equipped weapon set" or
            result == "locked" and "locked" or result == "missing" and "unavailable" or "did not complete")
        equal(state.count("Use"), (result == "locked" or result == "missing") and 0 or 1)
        state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
        state.advance(10)
        equal(#state.messages, 1)
    end)
end
test("equip row checks availability before core call", function()
    local state = uiFixture()
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    state.wsf.available = false
    state.wsf.Equip = function() error("unavailable UI must not call core") end
    noMutation(state, function() state.fire(state.button(state.equipDialog, "Weapons"), "OnClick") end)
    onlyFailure(state, "unavailable")
end)
test("Classic Character panel: icons on PaperDollItemsFrame, panels above its weapon row", function()
    local state = uiFixture({classic = true})
    local items = state.env.PaperDollItemsFrame
    equal(state.controls.parent, items)
    same(state.controls.allPoints, {items})
    same(state.saveButton.points, {{"TOPLEFT", state.env.CharacterWristSlot, "BOTTOMLEFT", 0, -6}})
    same(state.equipButton.points, {{"TOPRIGHT", state.env.CharacterTrinket1Slot, "BOTTOMRIGHT", 0, -6}})
    for _, dialog in ipairs({state.saveDialog, state.equipDialog}) do
        same(dialog.points[1], {"BOTTOM", items, "BOTTOM", 0, 132})
    end
    state.fire(state.saveButton, "OnClick")
    equal(state.saveDialog:IsShown(), true, "save opens with no Equipment Manager pane")
end)
test("no items frame at all makes no controls and no error", function()
    local state = uiFixture({classic = true, noItemsFrame = true})
    equal(state.env.WeaponSetsForeverSaveDialog, nil)
    equal(state.env.WeaponSetsForeverEquipDialog, nil)
    equal(#state.messages, 0)
end)

test("custom dialogs capture headings, native rectangle colors, and button placement", function()
    local state = uiFixture()
    local items = state.env.PaperDollFrame.ItemsFrame
    equal(state.controls.parent, items)
    same(state.controls.allPoints, {items})
    equal(state.controls.mouseEnabled, nil, "container must not intercept slot clicks")
    local icons = {
        {state.saveButton, state.env.CharacterWristSlot,
            "Interface\\AddOns\\WeaponSetsForever\\Textures\\SaveIcon", "LEFT"},
        {state.equipButton, state.env.CharacterTrinket1Slot,
            "Interface\\Icons\\INV_Sword_04", "RIGHT"},
    }
    for _, case in ipairs(icons) do
        local button, slot, icon, side = case[1], case[2], case[3], case[4]
        equal(button.kind, "Button")
        equal(button.template, nil, "icon buttons use no text template")
        equal(button.text, "", "icon buttons have no label")
        equal(button.width, 28)
        equal(button.height, 28)
        same(button.points, {{"TOP" .. side, slot, "BOTTOM" .. side, 0, -6}},
            "aligned to the outer edge of its slot column")
        equal(button.icon.texturePath, icon)
        equal(button.icon.layer, "ARTWORK")
        same(button.icon.points, {{"TOPLEFT", 1, -1}, {"BOTTOMRIGHT", -1, 1}})
        same(button.highlight, {"Interface\\Buttons\\ButtonHilight-Square", "ADD"})
        same(button.textures[1].color, {0.12, 0.065, 0.035, 1})
        for index = 2, 5 do
            same(button.textures[index].color, {0.68, 0.49, 0.22, 1})
        end
    end
    for _, dialog in ipairs({state.saveDialog, state.equipDialog}) do
        equal(state.env[dialog:GetName()], dialog)
        equal(dialog.strata, "DIALOG")
        equal(dialog.mouseEnabled, true)
        same(dialog.points[1], {"BOTTOM", state.env.CharacterFrame.LeftPaneHost, "BOTTOM", 0, 124})
        equal(dialog.labels[1].text, "Weapon Sets Forever")
        equal(dialog.labels[1].template, "GameFontNormal")
        same(dialog.labels[1].textColor, {0.68, 0.49, 0.22})
        same(dialog.textures[1].color, {0.12, 0.065, 0.035, 1})
        equal(dialog.textures[1].layer, "BACKGROUND")
        same(dialog.textures[1].allPoints, {})
        for index = 2, 5 do
            same(dialog.textures[index].color, {0.68, 0.49, 0.22, 1})
            equal(dialog.textures[index].layer, "BORDER")
        end
        for index = 6, #dialog.textures do
            same(dialog.textures[index].color, {0.68, 0.49, 0.22, 1})
            equal(dialog.textures[index].layer, "ARTWORK")
        end
    end
    equal(state.saveDialog.editBox.font, "GameFontNormal")
    equal(state.saveDialog.editBox.autoFocus, false)
    same(state.saveDialog.editBox.textColor, {0.92, 0.83, 0.68})
    contains(state.saveDialog.labels[2].text, "spaces need no quotes")
    contains(state.saveDialog.labels[3].text, "existing native set")
    equal(state.saveDialog.saveButton:GetText(), "Save")
    equal(state.saveDialog.cancelButton:GetText(), "Cancel")
end)
test("missing side slot frames leave the UI uncreated without errors", function()
    local state = uiFixture({missingSlots = true})
    equal(state.env.WeaponSetsForeverSaveDialog, nil)
    equal(state.env.WeaponSetsForeverEquipDialog, nil)
    for _, item in ipairs(state.widgets) do
        if item.kind == "Button" then error("no WSF buttons expected") end
    end
end)

test("icon buttons disable and desaturate when unavailable", function()
    local state = uiFixture()
    for _, button in ipairs({state.saveButton, state.equipButton}) do
        equal(button.enabled, true)
        equal(button.icon.desaturated, false)
    end
    state.wsf.available = false
    state.fire(state.controls, "OnShow")
    for _, button in ipairs({state.saveButton, state.equipButton}) do
        equal(button.enabled, false)
        equal(button.icon.desaturated, true)
    end
end)

test("dialog Escape registration is named and occurs only once", function()
    local state = uiFixture()
    same(state.env.UISpecialFrames, {"WeaponSetsForeverEquipDialog", "WeaponSetsForeverSaveDialog"})
    local count = #state.widgets
    for _ = 1, 3 do
        state.emit("ADDON_LOADED", "OtherAddOn")
        state.emit("PLAYER_REGEN_ENABLED")
        state.controls:Hide()
        state.controls:Show()
    end
    equal(#state.widgets, count)
    same(state.env.UISpecialFrames, {"WeaponSetsForeverEquipDialog", "WeaponSetsForeverSaveDialog"})
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    state.escape()
    equal(state.equipDialog:IsShown(), false)
    equal(state.count("Use"), 0)
end)
test("save Cancel and equip close button hide without mutation", function()
    local state, dialog, edit = savePrompt()
    noMutation(state, function() state.fire(dialog.cancelButton, "OnClick") end)
    equal(dialog:IsShown(), false)
    equal(edit.focus, false)
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    noMutation(state, function() state.fire(state.button(state.equipDialog, "X"), "OnClick") end)
    equal(state.equipDialog:IsShown(), false)
    equal(#state.messages, 0)
end)
test("equip paging shows eight rows and clears unused row IDs", function()
    local state = uiFixture()
    for index = 1, 10 do state.addSet(index, string.format("Set %02d", index)) end
    state.fire(state.equipButton, "OnClick")
    local dialog = state.equipDialog
    equal(dialog.pageText:GetText(), "1 / 2")
    equal(dialog.previous:IsEnabled(), false)
    equal(dialog.next:IsEnabled(), true)
    for index = 1, 8 do
        local row = state.button(dialog, string.format("Set %02d", index))
        equal(row.setID, index)
        equal(row:IsShown(), true)
    end
    local oldRow = state.button(dialog, "Set 08")
    state.fire(oldRow, "OnEnter")
    equal(state.env.GameTooltip:IsShown(), true)
    state.fire(dialog.next, "OnClick")
    equal(state.env.GameTooltip:IsShown(), false)
    equal(dialog.pageText:GetText(), "2 / 2")
    equal(dialog.previous:IsEnabled(), true)
    equal(dialog.next:IsEnabled(), false)
    equal(state.button(dialog, "Set 09").setID, 9)
    equal(state.button(dialog, "Set 10").setID, 10)
    equal(oldRow:IsShown(), false)
    equal(oldRow.setID, nil)
    equal(oldRow.setName, nil)
    noMutation(state, function() state.fire(oldRow, "OnClick") end)
    state.fire(dialog.previous, "OnClick")
    equal(dialog.pageText:GetText(), "1 / 2")
    equal(oldRow.setID, 8)
    state.fire(state.equipButton, "OnClick")
    equal(dialog:IsShown(), false, "equip button toggles closed")
    state.fire(state.equipButton, "OnClick")
    equal(dialog.pageText:GetText(), "1 / 2")
end)
test("equip list can open and page in combat without equipment changes", function()
    local state = uiFixture()
    for index = 1, 10 do state.addSet(index, string.format("Set %02d", index)) end
    state.combat = true
    noMutation(state, function()
        state.fire(state.equipButton, "OnClick")
        equal(state.equipDialog:IsShown(), true)
        equal(state.equipDialog.pageText:GetText(), "1 / 2")
        state.fire(state.equipDialog.next, "OnClick")
        equal(state.equipDialog.pageText:GetText(), "2 / 2")
        equal(state.button(state.equipDialog, "Set 10").setID, 10)
        state.emit("PLAYER_REGEN_DISABLED")
        equal(state.equipDialog:IsShown(), true)
        state.fire(state.equipDialog.previous, "OnClick")
        equal(state.equipDialog.pageText:GetText(), "1 / 2")
    end)
    equal(#state.messages, 0)
    equal(state.count("Use"), 0)
    equal(#state.timers, 0)
end)
test("equip list refreshes on native set changes and closes when empty", function()
    local state = uiFixture()
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    state.addSet(8, "Alpha")
    state.emit("EQUIPMENT_SETS_CHANGED")
    equal(state.button(state.equipDialog, "Alpha").setID, 8)
    state.sets, state.order = {}, {}
    state.emit("EQUIPMENT_SETS_CHANGED")
    equal(state.equipDialog:IsShown(), false)
    onlyFailure(state, "No weapon sets found")
end)
test("equip list reports read failure once and closes", function()
    local state = uiFixture()
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    state.wsf.GetWeaponSets = function() return nil, "mock list failure" end
    state.emit("EQUIPMENT_SETS_CHANGED")
    equal(state.equipDialog:IsShown(), false)
    onlyFailure(state, "mock list failure")
end)
test("control and row tooltips show and hide with combat-specific save warning", function()
    local state = uiFixture()
    local tooltip = state.env.GameTooltip
    state.combat = true
    state.fire(state.saveButton, "OnEnter")
    equal(tooltip:IsShown(), true)
    equal(tooltip.owner, state.saveButton)
    equal(tooltip.anchor, "ANCHOR_RIGHT")
    equal(tooltip.text, "WSF: Save weapons")
    contains(tooltip.lines[1][1], "regardless of creator")
    contains(tooltip.lines[2][1], "cannot be saved in combat")
    state.fire(state.saveButton, "OnLeave")
    equal(tooltip:IsShown(), false)
    state.fire(state.equipButton, "OnEnter")
    equal(tooltip.owner, state.equipButton)
    equal(tooltip.anchor, "ANCHOR_LEFT", "opens up and left, inside the paper doll")
    equal(tooltip.text, "WSF: Equip weapons")
    equal(#tooltip.lines, 1, "no combat save warning for equip")
    equal(tooltip.lines[1][1], "Equip a weapon set outside combat. Use native /equipset macros in combat.")
    state.fire(state.equipButton, "OnLeave")
    equal(tooltip:IsShown(), false)
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    local row = state.button(state.equipDialog, "Weapons")
    state.fire(row, "OnEnter")
    equal(tooltip.owner, row)
    equal(tooltip.text, "Weapons")
    equal(tooltip:IsShown(), true)
    state.fire(row, "OnLeave")
    equal(tooltip:IsShown(), false)
    state.wsf.available = false
    state.fire(state.equipButton, "OnEnter")
    contains(tooltip.lines[2][1], "unavailable")
end)
for _, prompt in ipairs({"save", "equip"}) do
    local which = prompt
    test("Character parent hides " .. which .. " dialog and tooltip", function()
        local state = uiFixture()
        if which == "save" then
            state.fire(state.saveButton, "OnClick")
            state.fire(state.saveButton, "OnEnter")
        else
            state.addSet(7, "Weapons")
            state.fire(state.equipButton, "OnClick")
            state.fire(state.button(state.equipDialog, "Weapons"), "OnEnter")
        end
        equal(state.env.GameTooltip:IsShown(), true)
        state.env.CharacterFrame:Hide()
        equal(state.saveDialog:IsShown(), false)
        equal(state.equipDialog:IsShown(), false)
        equal(state.saveDialog.editBox.focus, false)
        equal(state.env.GameTooltip:IsShown(), false)
        state.env.CharacterFrame:Show()
        equal(state.saveDialog:IsShown(), false)
        equal(state.equipDialog:IsShown(), false)
        equal(state.count("Use"), 0)
        equal(state.count("Save"), 0)
    end)
end
test("opening either dialog closes the other", function()
    local state, dialog, edit = savePrompt()
    state.addSet(7, "Weapons")
    state.fire(state.equipButton, "OnClick")
    equal(dialog:IsShown(), false)
    equal(edit.focus, false)
    equal(state.equipDialog:IsShown(), true)
    state.fire(state.saveButton, "OnClick")
    equal(state.equipDialog:IsShown(), false)
    equal(dialog:IsShown(), true)
    equal(edit.focus, true)
end)
for _, uiFirst in ipairs({false, true}) do
    local first = uiFirst
    test("UI availability is clean with " .. (first and "UI" or "core") .. " login handler first", function()
        local state = uiFixture({uiFirst = first})
        equal(state.wsf.available, true)
        equal(state.saveButton:IsEnabled(), true)
        equal(state.equipButton:IsEnabled(), true)
        equal(#state.messages, 0)
        equal(#state.timers, 0)
        state.fire(state.saveButton, "OnClick")
        equal(state.saveDialog:IsShown(), true)
    end)
    test("missing timer stays clean with " .. (first and "UI" or "core") .. " login handler first", function()
        local state = uiFixture({uiFirst = first, missingTimer = true})
        equal(state.wsf.available, false)
        equal(state.saveButton:IsEnabled(), false)
        equal(state.equipButton:IsEnabled(), false)
        onlyFailure(state, "Required timer API is unavailable")
        state.emit("ADDON_LOADED", "OtherAddOn")
        state.emit("PLAYER_REGEN_ENABLED")
        state.emit("PLAYER_LOGIN")
        equal(#state.messages, 1)
        equal(#state.timers, 0)
        noMutation(state, function()
            rejected(state.wsf.Save("Weapons"))
            rejected(state.wsf.Equip(7))
        end)
        equal(state.saveDialog:IsShown(), false)
        equal(state.equipDialog:IsShown(), false)
    end)
end

local function betaSparseTables(entry)
    for slot = 1, 19 do
        entry.ignored[slot] = not weapon(slot)
        if not weapon(slot) or entry.locations[slot] == 0 then
            entry.locations[slot] = nil
        end
    end
end

test("save verifies observed Shield-Set beta result tables", function()
    local state = fixture()
    state.gear[16], state.gear[17], state.gear[18] = 2011, 6320, nil
    state.afterSave = function(id)
        local entry = state.sets[id]
        entry.locations[16], entry.locations[17] = 1048592, 1048593
        betaSparseTables(entry)
    end
    local gear, flags = copy(state.gear), copy(state.flags)
    equal(state.wsf.Save("Shield-Set"), true)
    same(state.gear, gear)
    same(state.flags, flags)
    same(state.wsf.GetWeaponSets(), {{id = 100, name = "Shield-Set"}})
    local nativeTables = copy(state.sets)
    equal(state.wsf.PrepareEquip(100).name, "Shield-Set")
    same(state.sets, nativeTables, "verification does not mutate native tables")
end)

for _, slot in ipairs({16, 17, 18}) do
    local slotID = slot
    test("save accepts beta omitted empty slot with explicit false flag " .. slotID, function()
        local state = fixture()
        state.gear[slotID] = nil
        state.afterSave = function(id) betaSparseTables(state.sets[id]) end
        equal(state.wsf.Save("Empty"), true)
        equal(state.sets[100].locations[slotID], nil)
    end)
end

test("listing accepts omitted ignored locations", function()
    local state = fixture()
    local entry = state.addSet(7, "Weapons")
    for slot = 1, 19 do
        if not weapon(slot) then entry.locations[slot] = nil end
    end
    same(state.wsf.GetWeaponSets(), {{id = 7, name = "Weapons"}})
end)

test("beta omitted occupied location is not treated as empty", function()
    local state = fixture()
    local entry = state.addSet(7, "Weapons")
    betaSparseTables(entry)
    entry.locations[16] = nil
    noMutation(state, function() rejected(state.wsf.PrepareEquip(7)) end)
end)

test("beta omitted empty slot still requires explicit non-ignored flag", function()
    local state = fixture()
    local entry = state.addSet(7, "Weapons")
    betaSparseTables(entry)
    entry.ignored[18] = nil
    noMutation(state, function() rejected(state.wsf.PrepareEquip(7)) end)
end)

test("beta missing sentinel is not treated as omitted empty", function()
    local state = fixture()
    local entry = state.addSet(7, "Weapons")
    betaSparseTables(entry)
    entry.locations[18] = -1
    noMutation(state, function() rejected(state.wsf.PrepareEquip(7)) end)
end)

local acceptedProbes = {
    {"debug_probe Daggers", "Daggers"}, {"DEBUG_PROBE Daggers", "Daggers"},
    {'  debug_probe\t"Tank Weapons"  ', "Tank Weapons"},
    {"debug_probe " .. string.rep("a", 17), string.rep("a", 17)},
    {"debug_probe A|B", "A|B"},
    {"export Daggers", "Daggers"}, {'EXPORT "Tank Weapons"', "Tank Weapons"},
}
for index, case in ipairs(acceptedProbes) do
    local input, expected = case[1], case[2]
    test("probe parser accepts case " .. index, function()
        local valid, name = fixture().wsf.ParseProbeCommand(input)
        equal(valid, true)
        equal(name, expected)
    end)
end
for _, input in ipairs({"debug_probe", " DEBUG_PROBE \t", "export", " Export "}) do
    local message = input
    test("probe parser accepts no argument: " .. message, function()
        local valid, name = fixture().wsf.ParseProbeCommand(message)
        equal(valid, true)
        equal(name, nil)
    end)
end
local invalidProbes = {
    'debug_probe ""', 'debug_probe "   "',
    "debug_probe Tank Weapons", 'debug_probe "Name" extra', 'debug_probe "Name',
    'debug_probe Na"me', 'debug_probe "a\nb"',
}
for index, input in ipairs(invalidProbes) do
    local message = input
    test("probe parser rejects case " .. index .. " with one usage message", function()
        local state = fixture()
        noMutation(state, function()
            rejected(state.wsf.ParseProbeCommand(message))
            state.wsf.HandleCommand(message)
        end)
        onlyFailure(state, "Use /wsf debug_probe")
    end)
end
for _, input in ipairs({'export ""', "export Tank Weapons", 'EXPORT "Name'}) do
    local message = input
    test("export rejects malformed name with export usage: " .. message, function()
        local state = fixture()
        noMutation(state, function() state.wsf.HandleCommand(message) end)
        onlyFailure(state, "Use /wsf export, /wsf export Name,")
    end)
end
test("export and debug_probe print identical JSON with the typed command word", function()
    local state = fixture()
    state.addSet(7, "Other")
    state.addSet(8, "Weapons").equipped = true
    for _, arguments in ipairs({"", " Weapons", ' "Other"'}) do
        state.messages = {}
        noMutation(state, function()
            state.wsf.HandleCommand("debug_probe" .. arguments)
            state.wsf.HandleCommand("EXPORT" .. arguments)
        end)
        equal(#state.messages, 2)
        local probe = state.messages[1]:match("^WSF: debug_probe (.+)$")
        equal(state.messages[2], "WSF: export " .. probe)
    end
end)
test("export reports unknown sets once", function()
    local state = fixture()
    noMutation(state, function() state.wsf.HandleCommand("export Missing") end)
    onlyFailure(state, "No equipment set is named Missing.")
end)
for _, input in ipairs({'debug_probe"Name"', "debug_probeName", "exportName", "exports"}) do
    local message = input
    test("unseparated probe word is an unknown command: " .. message, function()
        local state = fixture()
        rejected(state.wsf.ParseProbeCommand(message))
        noMutation(state, function() state.wsf.HandleCommand(message) end)
        onlyFailure(state, "Use /wsf save")
    end)
end
test("save parser does not accept the probe command", function()
    rejected(fixture().wsf.ParseSaveCommand("debug_probe Daggers"))
end)

for _, case in ipairs({{"debug_swap", nil}, {" DEBUG_SWAP ", nil},
    {"debug_swap on", true}, {"debug_swap OFF", false}}) do
    local input, expected = case[1], case[2]
    test("swap debug parser accepts " .. input, function()
        local valid, setting = fixture().wsf.ParseSwapDebugCommand(input)
        equal(valid, true)
        equal(setting, expected)
    end)
end
for _, input in ipairs({"debug_swap maybe", "debug_swap on off", 'debug_swap "on"'}) do
    local message = input
    test("swap debug rejects " .. message .. " with usage", function()
        local state = fixture()
        noMutation(state, function() state.wsf.HandleCommand(message) end)
        onlyFailure(state, "Use /wsf debug_swap")
        equal(state.wsf.IsSwapDebugEnabled(), false)
    end)
end

local SWAP_STATE = "set=7 name=Weapons isEquipped=%s 16=%s 17=%s 18=nil"
test("swap debug is off by default and silent for swaps", function()
    local state, entry = equipFixture()
    equal(state.wsf.IsSwapDebugEnabled(), false)
    state.useHook = function(id)
        state.apply(id)
        state.emit("EQUIPMENT_SWAP_FINISHED", true, id)
        return true
    end
    equal(state.wsf.Equip(entry.id), true)
    same(state.messages, {"WSF: Equipped weapon set: Weapons"})
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    state.advance(1)
    equal(#state.messages, 1)
end)

test("swap debug reports native swaps at the event and one second later", function()
    local state = equipFixture()
    state.wsf.HandleCommand("debug_swap on")
    contains(state.messages[1], "WSF: debug_swap on:")
    state.messages = {}
    noMutation(state, function()
        state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
        state.advance(1)
    end)
    same(state.messages, {
        "WSF: debug_swap event " .. SWAP_STATE:format("false", 1016, 1017) .. " result=true",
        "WSF: debug_swap event+1s " .. SWAP_STATE:format("false", 1016, 1017),
    })
end)

test("swap debug traces a WSF swap without changing its outcome", function()
    local state, entry = equipFixture()
    state.wsf.SetSwapDebug(true)
    state.useHook = function() return true end
    equal(state.wsf.Equip(entry.id), true)
    state.apply(entry.id)
    state.emit("EQUIPMENT_SWAP_FINISHED", true, entry.id)
    state.advance(1)
    same(state.messages, {
        "WSF: debug_swap use " .. SWAP_STATE:format("false", 1016, 1017) .. " accepted=true",
        "WSF: Equipped weapon set: Weapons",
        "WSF: debug_swap finish " .. SWAP_STATE:format("true", 9001, 9002)
            .. " via=event success=true",
        "WSF: debug_swap event " .. SWAP_STATE:format("true", 9001, 9002) .. " result=true",
        "WSF: debug_swap event+1s " .. SWAP_STATE:format("true", 9001, 9002),
    })
end)

test("swap debug reports the fallback check", function()
    local state, entry = equipFixture()
    state.wsf.SetSwapDebug(true)
    state.useHook = function() return true end
    equal(state.wsf.Equip(entry.id), true)
    state.messages = {}
    state.advance(5)
    contains(state.messages[1], "did not complete")
    contains(state.messages[2], "WSF: debug_swap finish set=7")
    contains(state.messages[2], "via=fallback success=false")
end)

-- A diagnostic defect must surface as an error yet never strand a pending swap.
-- The observed client failure: diagnostics read a table that an older
-- Equipment.lua does not define. Only diagnostics depend on it.
local function breakDiagnostics(state)
    state.wsf.WEAPON_SLOT_IDS = nil
end
test("diagnostic defect at the use stage clears pending and propagates", function()
    local state, entry = equipFixture()
    state.wsf.SetSwapDebug(true)
    state.useHook = function() return true end
    breakDiagnostics(state)
    raises(function() state.wsf.Equip(entry.id) end, "ipairs")
    state.wsf.SetSwapDebug(false)
    state.messages = {}
    equal(state.wsf.Equip(entry.id), true, "a later swap is not blocked")
    equal(#state.messages, 0)
end)
test("diagnostic defect at the event stage still finishes the swap", function()
    local state, entry = equipFixture()
    state.useHook = function() return true end
    equal(state.wsf.Equip(entry.id), true)
    state.wsf.SetSwapDebug(true)
    breakDiagnostics(state)
    state.apply(entry.id)
    raises(function() state.emit("EQUIPMENT_SWAP_FINISHED", true, entry.id) end, "ipairs")
    equal(state.messages[1], "WSF: Equipped weapon set: Weapons")
    state.wsf.SetSwapDebug(false)
    state.messages = {}
    equal(state.wsf.Equip(entry.id), true, "no stranded pending swap")
end)
test("diagnostic defect at the fallback stage still finishes the swap", function()
    local state, entry = equipFixture()
    state.useHook = function() return true end
    equal(state.wsf.Equip(entry.id), true)
    state.wsf.SetSwapDebug(true)
    breakDiagnostics(state)
    raises(function() state.advance(5) end, "ipairs")
    contains(state.messages[1], "did not complete")
    state.wsf.SetSwapDebug(false)
    state.messages = {}
    equal(state.wsf.Equip(entry.id), true, "no stranded pending swap")
end)
for _, name in ipairs({"WeaponsMatchSet", "ProbeEquipped", "ParseSwapDebugCommand"}) do
    local missing = name
    test("login reports a mixed install missing " .. missing, function()
        local state = fixture(false)
        state.wsf[missing] = nil
        state.emit("PLAYER_LOGIN")
        equal(state.wsf.available, false)
        state.takeBanner(false)
        onlyFailure(state, "files are from different versions (missing " .. missing .. ")")
    end)
end
test("login reports a mixed install missing the weapon slot table", function()
    local state = fixture(false)
    state.wsf.WEAPON_SLOT_IDS = nil
    state.emit("PLAYER_LOGIN")
    equal(state.wsf.available, false)
    state.takeBanner(false)
    onlyFailure(state, "missing WEAPON_SLOT_IDS")
end)

test("swap debug status counts client swap events even while off", function()
    local state = equipFixture()
    noMutation(state, function()
        state.wsf.HandleCommand("debug_swap status")
        state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
        state.emit("EQUIPMENT_SWAP_FINISHED", false, 7)
        state.wsf.HandleCommand("DEBUG_SWAP STATUS")
    end)
    same(state.messages, {
        "WSF: debug_swap status enabled=false available=true events=0 lastResult=nil lastSet=nil pending=false canUse=true",
        "WSF: debug_swap test set=nil name=nil isEquipped=nil 16=1016 17=1017 18=nil",
        "WSF: debug_swap status enabled=false available=true events=2 lastResult=false lastSet=7 pending=false canUse=true",
        "WSF: debug_swap test " .. SWAP_STATE:format("false", 1016, 1017),
    })
end)

test("swap debug status reports formatting errors as chat text", function()
    local state = equipFixture()
    state.wsf.WEAPON_SLOT_IDS = nil
    state.wsf.HandleCommand("debug_swap status")
    equal(#state.messages, 2)
    contains(state.messages[2], "WSF: debug_swap test failed: ")
    contains(state.messages[2], "ipairs")
end)

test("swap debug status works while unavailable without reading APIs", function()
    local state = fixture(false)
    state.env.C_EquipmentSet = nil
    state.wsf.HandleCommand("debug_swap status")
    same(state.messages, {
        "WSF: debug_swap status enabled=false available=false events=0 lastResult=nil lastSet=nil pending=false canUse=nil",
    })
end)

test("swap debug toggles without an argument and turns off", function()
    local state = fixture()
    state.wsf.HandleCommand("debug_swap")
    equal(state.wsf.IsSwapDebugEnabled(), true)
    state.wsf.HandleCommand("debug_swap")
    equal(state.wsf.IsSwapDebugEnabled(), false)
    equal(state.messages[2], "WSF: debug_swap off.")
    state.messages = {}
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    equal(#state.messages, 0)
end)

test("swap debug requires availability and never reads missing APIs", function()
    local state = fixture(false)
    noMutation(state, function() state.wsf.HandleCommand("debug_swap on") end)
    onlyFailure(state, "unavailable")
    equal(state.wsf.IsSwapDebugEnabled(), false)
    state.wsf.SetSwapDebug(true)
    state.env.C_EquipmentSet = nil
    state.messages = {}
    state.emit("EQUIPMENT_SWAP_FINISHED", true, 7)
    equal(#state.messages, 0)
end)

local function slotJSON(values)
    local fields = {}
    for slot = 1, 19 do
        local value = values[slot]
        fields[#fields + 1] = '"' .. slot .. '":' .. (value == nil and "null" or tostring(value))
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

test("probe prints raw sparse native tables and current gear without mutation", function()
    local state = fixture()
    state.gear[16], state.gear[17], state.gear[18] = 2011, 6320, nil
    state.afterSave = function(id)
        local entry = state.sets[id]
        entry.locations[16], entry.locations[17] = 1048592, 1048593
        betaSparseTables(entry)
    end
    equal(state.wsf.Save("Shield-Set"), true)
    state.messages = {}
    local ignored, current = {}, {}
    for slot = 1, 19 do
        ignored[slot] = not weapon(slot)
        current[slot] = state.gear[slot]
    end
    local equipped = '{"kind":"equipped","hex":"0x1000%s","player":true,"bags":false,'
        .. '"bank":false,"bag":0,"slot":%d}'
    local expected = "WSF: debug_probe {"
        .. '"client":{"version":"1.60.1","build":"70450","interface":16001},'
        .. '"name":"Shield-Set","id":100,"info":{"name":"Shield-Set","iconFileID":"icon",'
        .. '"setID":100,"isEquipped":false,"numItems":null,"numEquipped":null,'
        .. '"numInInventory":null,"numLost":null,"numIgnored":null},'
        .. '"ignored":' .. slotJSON(ignored) .. ","
        .. '"locations":' .. slotJSON({[16] = 1048592, [17] = 1048593}) .. ","
        .. '"decodedLocations":' .. slotJSON({
            [16] = equipped:format("10", 16), [17] = equipped:format("11", 17),
        }) .. ","
        .. '"items":' .. slotJSON({[16] = 2011, [17] = 6320}) .. ","
        .. '"current":' .. slotJSON(current) .. "}"
    noMutation(state, function() state.wsf.HandleCommand("debug_probe Shield-Set") end)
    same(state.messages, {expected})
end)

test("probe shows full outfits and unexpected keys without validating them", function()
    local state = fixture()
    local entry = state.addSet(7, "Outfit", true)
    entry.items[0], entry.items.extra, entry.items[16] = 55, "x", 0 / 0
    local json = state.wsf.ProbeSet("Outfit")
    contains(json, '"items":{"0":55,"1":1001,')
    contains(json, '"16":null,')
    contains(json, '"19":1019,"extra":"x"}')
    contains(json, '"ignored":{"1":null,')
end)

test("probe names all documented set info returns from client output", function()
    local state = fixture()
    state.addSet(1, "Ranged")
    state.env.C_EquipmentSet.GetEquipmentSetInfo = function()
        return "Ranged", 134400, 1, false, 3, 2, 1, 0, 0
    end
    contains(state.wsf.ProbeSet("Ranged"), '"info":{"name":"Ranged","iconFileID":134400,'
        .. '"setID":1,"isEquipped":false,"numItems":3,"numEquipped":2,'
        .. '"numInInventory":1,"numLost":0,"numIgnored":0},')
end)

test("probe keeps undocumented extra set info returns, including trailing nil", function()
    local state = fixture()
    state.addSet(1, "Ranged")
    state.env.C_EquipmentSet.GetEquipmentSetInfo = function()
        return "Ranged", 134400, 1, false, 3, 2, 1, 0, 0, "new", nil
    end
    contains(state.wsf.ProbeSet("Ranged"), '"numIgnored":0,"extraReturns":["new",null]},')
end)

local decodedLocations = {
    {3146499, '{"kind":"bags","hex":"0x300303","player":true,"bags":true,'
        .. '"bank":false,"bag":3,"slot":3}'},
    {1048592 + 2 ^ 22, '{"kind":"bank","hex":"0x500010","player":true,"bags":false,'
        .. '"bank":true,"bag":0,"slot":16}'},
    {1048592 + 2 ^ 23, '{"kind":"equipped","hex":"0x900010","player":true,"bags":false,'
        .. '"bank":false,"bag":0,"slot":16,"otherBits":"0x800000"}'},
    {0, '{"kind":"empty"}'}, {1, '{"kind":"ignored"}'}, {-1, '{"kind":"missing"}'},
    {-2, '{"kind":"unknown"}'}, {2.5, '{"kind":"unknown"}'}, {"x", '{"kind":"unknown"}'},
}
for index, case in ipairs(decodedLocations) do
    local location, expected = case[1], case[2]
    test("probe decodes location case " .. index, function()
        local state = fixture()
        local entry = state.addSet(7, "Weapons")
        entry.locations[18] = location
        contains(state.wsf.ProbeSet("Weapons"), '"18":' .. expected .. ',"19":')
    end)
end

test("probe escapes JSON and chat control characters in native names", function()
    local state = fixture()
    local name = 'A"B\\C|D\tE'
    state.addSet(7, name)
    local json = state.wsf.ProbeSet(name)
    contains(json, '"name":"A\\"B\\\\C\\u007cD\\u0009E"')
    equal(json:find("|", 1, true), nil, "raw | would start a chat escape")
end)

test("probe reports unknown sets once without mutation", function()
    local state = fixture()
    noMutation(state, function() state.wsf.HandleCommand('debug_probe "No Such Set"') end)
    onlyFailure(state, "No equipment set is named No Such Set.")
end)

test("probe is read-only and permitted in combat", function()
    local state = fixture()
    state.addSet(7, "Weapons")
    state.combat = true
    noMutation(state, function() state.wsf.HandleCommand("debug_probe Weapons") end)
    equal(#state.messages, 1)
    contains(state.messages[1], 'WSF: debug_probe {"client":')
end)

for _, input in ipairs({"debug_probe Weapons", "debug_probe"}) do
    local message = input
    test("probe requires login availability: " .. message, function()
        local state = fixture(false)
        state.addSet(7, "Weapons")
        noMutation(state, function() state.wsf.HandleCommand(message) end)
        onlyFailure(state, "unavailable")
    end)
end

local function currentGearJSON(state)
    local current = {}
    for slot = 1, 19 do current[slot] = state.gear[slot] end
    return slotJSON(current)
end

test("probe without a name reports current gear when no set is equipped", function()
    local state = fixture()
    state.addSet(7, "Weapons")
    -- Only a literal true flag counts as equipped.
    state.env.C_EquipmentSet.GetEquipmentSetInfo = function(id)
        return state.sets[id].name, "icon", id, 1
    end
    noMutation(state, function() state.wsf.HandleCommand("debug_probe") end)
    same(state.messages, {'WSF: debug_probe {"client":{"version":"1.60.1","build":"70450",'
        .. '"interface":16001},"name":null,"id":null,"current":' .. currentGearJSON(state) .. "}"})
end)

test("probe without a name reports current gear when there are no sets", function()
    local state = fixture()
    noMutation(state, function() state.wsf.HandleCommand("debug_probe") end)
    equal(#state.messages, 1)
    contains(state.messages[1], '"name":null,"id":null,"current":')
end)

test("probe without a name reports the equipped set like a named probe", function()
    local state = fixture()
    state.addSet(7, "Other")
    state.addSet(8, "Weapons").equipped = true
    state.wsf.HandleCommand("debug_probe Weapons")
    local named = state.messages[1]
    state.messages = {}
    noMutation(state, function() state.wsf.HandleCommand("debug_probe") end)
    same(state.messages, {named})
end)

test("probe without a name reports every set the client marks equipped", function()
    local state = fixture()
    state.addSet(7, "Alpha").equipped = true
    state.addSet(8, "Unequipped")
    state.addSet(9, "Beta").equipped = true
    noMutation(state, function() state.wsf.HandleCommand("debug_probe") end)
    equal(#state.messages, 2)
    contains(state.messages[1], '"name":"Alpha","id":7,')
    contains(state.messages[2], '"name":"Beta","id":9,')
end)

test("probe without a name is permitted in combat", function()
    local state = fixture()
    state.combat = true
    noMutation(state, function() state.wsf.HandleCommand("debug_probe") end)
    equal(#state.messages, 1)
    contains(state.messages[1], 'WSF: debug_probe {"client":')
end)

test("source retains native slash ownership without custom combat macro or queue paths", function()
    local function source(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local commands = source("Commands.lua")
    contains(commands, 'command ~= "save"')
    equal(commands:find("equipset", 1, true), nil, "save parser must not parse native equipset")
    local core = source("Core.lua")
    contains(core, 'SLASH_ALIASES = {"/wsf", "/weaponsets"}')
    contains(core, "SlashCmdList[SLASH_KEY] = WSF.HandleCommand")
    equal(core:find("PLAYER_REGEN_ENABLED", 1, true), nil, "no core combat-exit equip queue")
    local equipment = source("Equipment.lua")
    equal(equipment:find("PLAYER_REGEN_ENABLED", 1, true), nil, "no equipment combat-exit queue")
    -- These source checks limit AddOn scope; mocks cannot prove native /equipset combat behavior.
    for _, text in ipairs({commands, equipment, core, source("UI.lua")}) do
        for _, forbidden in ipairs({"/wsf set", "RunMacro", "SecureActionButtonTemplate",
            "SecureHandler", "SetAttribute", 'SlashCmdList["EQUIP_SET"]',
            "SLASH_EQUIP_SET", "OnUpdate"}) do
            equal(text:find(forbidden, 1, true), nil, "unexpected custom path: " .. forbidden)
        end
    end
    local state = fixture()
    equal(state.env.SLASH_WEAPONSETSFOREVER1, "/wsf")
    equal(state.env.SLASH_WEAPONSETSFOREVER2, "/weaponsets")
    equal(state.env.SLASH_WEAPONSETSFOREVER3, nil)
    for name in pairs(state.env.SlashCmdList) do
        equal(name, "WEAPONSETSFOREVER", "only the WSF command key is registered")
    end
    noMutation(state, function() state.wsf.HandleCommand("set Weapons") end)
    onlyFailure(state, "Use /wsf save")
end)

local failed = 0
for index, entry in ipairs(tests) do
    local ok, message = xpcall(entry.body, debug.traceback)
    if ok then
        io.write("ok ", index, " - ", entry.name, "\n")
    else
        failed = failed + 1
        io.write("not ok ", index, " - ", entry.name, "\n", tostring(message), "\n")
    end
end
io.write(string.format("\n%d tests: %d passed, %d failed\n", #tests, #tests - failed, failed))
io.write("Mock results do not establish in-client compatibility.\n")
os.exit(failed == 0 and 0 or 1)
