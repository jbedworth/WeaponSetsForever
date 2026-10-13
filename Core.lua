local addonName, WSF = ...

local pending
local SWAP_TIMEOUT_SECONDS = 5
local DEFAULT_TITLE = "Weapon Sets Forever"
local READY_MESSAGE = "  Ready. Use the Save and Equip icons in the Character panel, or /wsf save Name."
local SWAP_FAILED_MESSAGE = "The weapon swap did not complete. Some items may have changed. Check your weapons, item locks, and free bag space."
WSF.available = false

function WSF.Report(message)
    DEFAULT_CHAT_FRAME:AddMessage("WSF: " .. tostring(message))
end

-- Reads TOC fields so the banner follows the packaged version; never gates operations.
local function Metadata(field)
    if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnMetadata) ~= "function" then
        return nil
    end
    local value = C_AddOns.GetAddOnMetadata(addonName, field)
    if type(value) == "string" and value:find("%S") then
        return value
    end
end

local function ReportLoaded(available)
    local banner = Metadata("Title") or DEFAULT_TITLE
    local version, author = Metadata("Version"), Metadata("Author")
    if version then
        banner = banner .. " " .. version
    end
    if author then
        banner = banner .. " by " .. author
    end
    WSF.Report(banner)
    if available then
        WSF.Report(READY_MESSAGE)
    end
end

-- Session-only swap diagnostics; off by default and never persisted. They run
-- only after swap state is settled, so a diagnostic defect cannot strand a swap.
local swapDebug = false
local SWAP_DEBUG_DELAY_SECONDS = 1

function WSF.SetSwapDebug(enabled)
    swapDebug = enabled == true
    return swapDebug
end

function WSF.IsSwapDebugEnabled()
    return swapDebug
end

-- Counted for every client swap event, so status shows whether events arrive.
local swapEvents = {count = 0}

local function FormatSwapState(stage, setID, details)
    local name, isEquipped
    if type(setID) == "number" then
        local _
        name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    end
    local weapons = {}
    for _, slot in ipairs(WSF.WEAPON_SLOT_IDS) do
        -- An empty slot returns no value at all, which tostring() rejects.
        local item = GetInventoryItemID("player", slot)
        weapons[#weapons + 1] = slot .. "=" .. tostring(item)
    end
    return string.format("debug_swap %s set=%s name=%s isEquipped=%s %s%s",
        stage, tostring(setID), tostring(name), tostring(isEquipped),
        table.concat(weapons, " "), details and (" " .. details) or "")
end

local function ReportSwapState(stage, setID, details)
    -- Unsupported clients may lack the APIs read here.
    if not swapDebug or not WSF.available then
        return
    end
    WSF.Report(FormatSwapState(stage, setID, details))
end

-- Reports why diagnostics may be silent. The protected call here only turns a
-- formatting error into chat text for this explicit status command; it does
-- not guard any swap or save path.
function WSF.ReportSwapDebugStatus()
    WSF.Report(string.format(
        "debug_swap status enabled=%s available=%s events=%d lastResult=%s lastSet=%s pending=%s",
        tostring(swapDebug), tostring(WSF.available), swapEvents.count,
        tostring(swapEvents.result), tostring(swapEvents.setID), tostring(pending ~= nil)))
    if not WSF.available then
        return
    end
    local ok, line = pcall(FormatSwapState, "test", swapEvents.setID)
    WSF.Report(ok and line or ("debug_swap test failed: " .. tostring(line)))
end

local function ReportSwapEvent(result, setID)
    if not swapDebug or not WSF.available then
        return
    end
    ReportSwapState("event", setID, "result=" .. tostring(result))
    C_Timer.After(SWAP_DEBUG_DELAY_SECONDS, function()
        ReportSwapState("event+" .. SWAP_DEBUG_DELAY_SECONDS .. "s", setID)
    end)
end

-- Functions other runtime files must define. A mixed install of old and new
-- files otherwise fails silently, because the client hides Lua errors by default.
local REQUIRED_NAMESPACE = {
    "ValidateName", "ParseSaveCommand", "ParseProbeCommand", "ParseSwapDebugCommand",
    "HandleCommand", "CheckCapabilities", "Save", "GetWeaponSets", "PrepareEquip",
    "ProbeSet", "ProbeEquipped", "WeaponsMatchSet",
}

local function CheckInstalledFiles()
    for _, name in ipairs(REQUIRED_NAMESPACE) do
        if type(WSF[name]) ~= "function" then
            return false, "AddOn files are from different versions (missing " .. name
                .. "). Reinstall every Weapon Sets Forever file, then restart the client."
        end
    end
    if type(WSF.WEAPON_SLOT_IDS) ~= "table" then
        return false, "AddOn files are from different versions (missing WEAPON_SLOT_IDS)."
            .. " Reinstall every Weapon Sets Forever file, then restart the client."
    end
    return true
end

-- The set's isEquipped flag can still be false when EQUIPMENT_SWAP_FINISHED
-- fires, and may never be true for a set of empty slots, so the weapon slots
-- themselves also confirm completion.
local function SwapVerified(operation)
    local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(operation.id)
    return equipped == true or WSF.WeaponsMatchSet(operation.id)
end

local function FinishSwap(operation, success, via)
    if pending ~= operation then
        return
    end
    pending = nil
    operation.finished = true
    operation.success = success
    if success then
        WSF.Report("Equipped weapon set: " .. operation.name)
    else
        operation.message = SWAP_FAILED_MESSAGE
        WSF.Report(operation.message)
    end
    ReportSwapState("finish", operation.id, "via=" .. via .. " success=" .. tostring(success))
end

-- A false result fails at once. A true result succeeds once state verifies it;
-- otherwise the next equipment change or the single fallback check decides.
local function HandleSwapFinished(operation, result)
    if not result then
        FinishSwap(operation, false, "event")
    elseif SwapVerified(operation) then
        FinishSwap(operation, true, "event")
    end
end

function WSF.Equip(id)
    if pending then
        local message = "A weapon swap is still pending. Wait for it to finish."
        WSF.Report(message)
        return false, message
    end
    local entry, message = WSF.PrepareEquip(id)
    if not entry then
        WSF.Report(message)
        return false, message
    end
    local operation = {id = id, name = entry.name}
    -- The completion event can fire inside UseEquipmentSet.
    pending = operation
    local ran, accepted = xpcall(function()
        local result = C_EquipmentSet.UseEquipmentSet(id)
        ReportSwapState("use", id, "accepted=" .. tostring(result))
        return result
    end, function(messageText)
        if type(debugstack) == "function" then
            return tostring(messageText) .. "\n" .. debugstack(2)
        end
        return messageText
    end)
    if not ran then
        if pending == operation then
            pending = nil
        end
        error(accepted, 0)
    end
    if operation.finished then
        return operation.success, operation.message
    end
    if not accepted then
        FinishSwap(operation, false, "rejected")
        return false, operation.message
    end
    if SwapVerified(operation) then
        FinishSwap(operation, true, "immediate")
    else
        C_Timer.After(SWAP_TIMEOUT_SECONDS, function()
            if pending == operation then
                FinishSwap(operation, SwapVerified(operation), "fallback")
            end
        end)
    end
    return true
end

SLASH_WEAPONSETSFOREVER1 = "/wsf"
SlashCmdList["WEAPONSETSFOREVER"] = WSF.HandleCommand

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:SetScript("OnEvent", function(self, event, result, setID)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        local available, message = CheckInstalledFiles()
        if available then
            available, message = WSF.CheckCapabilities()
        end
        if available and (type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function") then
            available = false
            message = "Required timer API is unavailable."
        end
        WSF.available = available
        ReportLoaded(available)
        if not available then
            WSF.Report(message)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- In client traces, items move after a true EQUIPMENT_SWAP_FINISHED,
        -- so the gear change itself confirms the swap.
        if pending and SwapVerified(pending) then
            FinishSwap(pending, true, "equipment")
        end
    else
        swapEvents.count = swapEvents.count + 1
        swapEvents.result, swapEvents.setID = result, setID
        if pending and (setID == pending.id or setID == nil) then
            HandleSwapFinished(pending, result)
        end
        -- Also reports native /equipset swaps, for comparison with WSF swaps.
        ReportSwapEvent(result, setID)
    end
end)
