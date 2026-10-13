local _, WSF = ...

local pending
local SWAP_TIMEOUT_SECONDS = 5
WSF.available = false

function WSF.Report(message)
    DEFAULT_CHAT_FRAME:AddMessage("WSF: " .. tostring(message))
end

local function FinishSwap(operation, result)
    if pending ~= operation then
        return
    end
    pending = nil
    operation.finished = true
    local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(operation.id)
    operation.success = result and equipped == true
    if operation.success then
        WSF.Report("Equipped weapon set: " .. operation.name)
    else
        operation.message = "The weapon swap did not complete. Some items may have changed. Check your weapons, item locks, and free bag space."
        WSF.Report(operation.message)
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
        return C_EquipmentSet.UseEquipmentSet(id)
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
        FinishSwap(operation, false)
        return false, operation.message
    end
    local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(id)
    if equipped then
        FinishSwap(operation, true)
    else
        C_Timer.After(SWAP_TIMEOUT_SECONDS, function()
            if pending == operation then
                FinishSwap(operation, true)
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
events:SetScript("OnEvent", function(self, event, result, setID)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        local available, message = WSF.CheckCapabilities()
        if available and (type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function") then
            available = false
            message = "Required timer API is unavailable."
        end
        WSF.available = available
        if not available then
            WSF.Report(message)
        end
    elseif pending and (setID == pending.id or setID == nil) then
        FinishSwap(pending, result)
    end
end)
