local addonName, WSF = ...

local SAVE_DIALOG = "WeaponSetsForeverSaveDialog"
local EQUIP_DIALOG = "WeaponSetsForeverEquipDialog"
local BUTTON_TEMPLATE = "SharedButtonSmallTemplate"
local BUTTON_WIDTH = 120
local BUTTON_HEIGHT = 28
local GAP = 6
-- Panels open above the weapon row, between the side slot columns.
local PANEL_BOTTOM_OFFSET = 124
local ICON_BUTTON_SIZE = 28
-- The Save icon is built from the logo by scripts/build_icon.py; the client
-- resolves the .tga extension. Equip uses a built-in client icon.
local SAVE_ICON = "Interface\\AddOns\\" .. addonName .. "\\Textures\\SaveIcon"
local EQUIP_ICON = "Interface\\Icons\\INV_Sword_04"
local ICON_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local LIST_WIDTH = 260
local SAVE_WIDTH = 300
local PANEL_INSET = 12
local GOLD = {0.68, 0.49, 0.22}
local WARM_TEXT = {0.92, 0.83, 0.68}
local ROW_HEIGHT = 28
local ROWS_PER_PAGE = 8
local COMBAT_MESSAGE = "Weapon sets cannot be saved in combat. Wait until combat ends."
local UNAVAILABLE_MESSAGE = "Weapon sets are unavailable on this client."

local controls
local selection
local saveDialog
local rows = {}
local sets = {}
local page = 1
local loggedIn = IsLoggedIn() and WSF.available ~= nil

local function CanOperate()
    if not WSF.available then
        WSF.Report(UNAVAILABLE_MESSAGE)
        return false
    end
    return true
end

local function CanSave()
    if not CanOperate() then
        return false
    end
    if InCombatLockdown() then
        WSF.Report(COMBAT_MESSAGE)
        return false
    end
    if PaperDollFrame and PaperDollFrame.EquipmentManagerPane
        and PaperDollFrame.EquipmentManagerPane:IsVisible() then
        WSF.Report("Close the Equipment Manager pane before saving.")
        return false
    end
    return true
end

local function AcceptSave(dialog)
    if not dialog:IsShown() then
        return
    end
    if not CanSave() then
        dialog.editBox:SetFocus()
        return
    end

    -- The edit box is a literal name, not a slash-command argument string.
    local name = dialog.editBox:GetText()
    local valid, message = WSF.ValidateName(name)
    if not valid then
        WSF.Report(message)
        dialog.editBox:SetFocus()
        return
    end

    local success, errorMessage = WSF.Save(name)
    if not success then
        WSF.Report(errorMessage or "Could not save the weapon set.")
        dialog.editBox:SetFocus()
        return
    end
    WSF.Report("Saved weapon set: " .. name)
    dialog:Hide()
end

local function RegisterEscape(name)
    for _, registered in ipairs(UISpecialFrames) do
        if registered == name then
            return
        end
    end
    table.insert(UISpecialFrames, name)
end

local function Rectangle(parent, layer, red, green, blue)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(red, green, blue, 1)
    return texture
end

local function StylePanel(frame)
    local background = Rectangle(frame, "BACKGROUND", 0.12, 0.065, 0.035)
    background:SetAllPoints()
    for _, edge in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        local border = Rectangle(frame, "BORDER", unpack(GOLD))
        if edge == "TOP" or edge == "BOTTOM" then
            border:SetPoint(edge .. "LEFT")
            border:SetPoint(edge .. "RIGHT")
            border:SetHeight(1)
        else
            border:SetPoint("TOP" .. edge)
            border:SetPoint("BOTTOM" .. edge)
            border:SetWidth(1)
        end
    end
end

local function PanelText(parent, text, gold)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetTextColor(unpack(gold and GOLD or WARM_TEXT))
    label:SetText(text)
    return label
end

local function Separator(parent, offset)
    local separator = Rectangle(parent, "ARTWORK", unpack(GOLD))
    separator:SetPoint("TOPLEFT", PANEL_INSET, offset)
    separator:SetPoint("TOPRIGHT", -PANEL_INSET, offset)
    separator:SetHeight(1)
end

local function CreatePanel(name, width, height)
    local panel = CreateFrame("Frame", name, controls)
    panel:SetSize(width, height)
    panel:SetPoint("BOTTOM", CharacterFrame.LeftPaneHost, "BOTTOM", 0, PANEL_BOTTOM_OFFSET)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:Hide()
    StylePanel(panel)
    local title = PanelText(panel, "Weapon Sets Forever", true)
    title:SetPoint("TOPLEFT", PANEL_INSET, -PANEL_INSET)
    Separator(panel, -34)
    RegisterEscape(name)
    return panel
end

local function CreateButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, BUTTON_TEMPLATE)
    button:SetSize(width or BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetText(text)
    return button
end

-- Icon-only buttons sit beneath a side slot column, clear of text that other
-- AddOns draw beside the slots and weapon row.
local function CreateIconButton(icon, slot)
    local button = CreateFrame("Button", nil, controls)
    button:SetSize(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE)
    button:SetPoint("TOP", slot, "BOTTOM", 0, -GAP)
    StylePanel(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexture(icon)
    button:SetHighlightTexture(ICON_HIGHLIGHT, "ADD")
    return button
end

local function CreateSaveDialog()
    saveDialog = CreatePanel(SAVE_DIALOG, SAVE_WIDTH, 226)
    local instructions = PanelText(saveDialog, "Save current weapons\nName: up to 16 letters; spaces need no quotes.")
    instructions:SetPoint("TOPLEFT", PANEL_INSET, -46)
    instructions:SetWidth(SAVE_WIDTH - 2 * PANEL_INSET)
    instructions:SetJustifyH("LEFT")

    local inputPanel = CreateFrame("Frame", nil, saveDialog)
    inputPanel:SetSize(SAVE_WIDTH - 2 * PANEL_INSET, 30)
    inputPanel:SetPoint("TOPLEFT", PANEL_INSET, -88)
    StylePanel(inputPanel)
    saveDialog.editBox = CreateFrame("EditBox", nil, saveDialog)
    local editBox = saveDialog.editBox
    editBox:SetPoint("TOPLEFT", inputPanel, "TOPLEFT", 8, -4)
    editBox:SetPoint("BOTTOMRIGHT", inputPanel, "BOTTOMRIGHT", -8, 4)
    editBox:SetFontObject("GameFontNormal")
    editBox:SetTextColor(unpack(WARM_TEXT))
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEnterPressed", function()
        AcceptSave(saveDialog)
    end)
    editBox:SetScript("OnEscapePressed", function()
        saveDialog:Hide()
    end)

    local warning = PanelText(saveDialog, "An existing native set with this name is replaced by a weapon-only snapshot.")
    warning:SetPoint("TOPLEFT", PANEL_INSET, -130)
    warning:SetWidth(SAVE_WIDTH - 2 * PANEL_INSET)
    warning:SetJustifyH("LEFT")
    Separator(saveDialog, -182)
    saveDialog.saveButton = CreateButton(saveDialog, "Save")
    saveDialog.saveButton:SetPoint("BOTTOMLEFT", PANEL_INSET, PANEL_INSET)
    saveDialog.saveButton:SetScript("OnClick", function()
        AcceptSave(saveDialog)
    end)
    saveDialog.cancelButton = CreateButton(saveDialog, "Cancel")
    saveDialog.cancelButton:SetPoint("BOTTOMRIGHT", -PANEL_INSET, PANEL_INSET)
    saveDialog.cancelButton:SetScript("OnClick", function()
        saveDialog:Hide()
    end)
    saveDialog:SetScript("OnShow", function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end)
    saveDialog:SetScript("OnHide", function(self)
        self.editBox:ClearFocus()
    end)
end

local function SetTooltip(button, title, description, saving)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(description, 1, 1, 1, true)
        if not WSF.available then
            GameTooltip:AddLine(UNAVAILABLE_MESSAGE, 1, 0.3, 0.3, true)
        elseif saving and InCombatLockdown() then
            GameTooltip:AddLine(COMBAT_MESSAGE, 1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function RenderPage()
    GameTooltip:Hide()
    local pageCount = math.max(1, math.ceil(#sets / ROWS_PER_PAGE))
    page = math.min(page, pageCount)
    for index, row in ipairs(rows) do
        local entry = sets[(page - 1) * ROWS_PER_PAGE + index]
        if entry then
            row.setID = entry.id
            row.setName = entry.name
            row:SetText(entry.name)
            row:Show()
        else
            row.setID = nil
            row.setName = nil
            row:Hide()
        end
    end
    selection.pageText:SetText(page .. " / " .. pageCount)
    selection.previous:SetEnabled(page > 1)
    selection.next:SetEnabled(page < pageCount)
end

local function RefreshSets()
    local result, message = WSF.GetWeaponSets()
    if not result then
        selection:Hide()
        WSF.Report(message or "Could not list weapon sets.")
        return false
    end
    sets = result
    if #sets == 0 then
        selection:Hide()
        WSF.Report("No weapon sets found. Save your current weapons first.")
        return false
    end
    RenderPage()
    return true
end

local function CreateSelection()
    selection = CreatePanel(EQUIP_DIALOG, LIST_WIDTH, 110 + ROWS_PER_PAGE * ROW_HEIGHT)
    local subtitle = PanelText(selection, "Choose a weapon set")
    subtitle:SetPoint("TOPLEFT", PANEL_INSET, -44)
    Separator(selection, -70 - ROWS_PER_PAGE * ROW_HEIGHT)

    local close = CreateButton(selection, "X", BUTTON_HEIGHT)
    close:SetPoint("TOPRIGHT", -GAP, -2)
    close:SetScript("OnClick", function()
        selection:Hide()
    end)

    for index = 1, ROWS_PER_PAGE do
        local row = CreateButton(selection, "", LIST_WIDTH - 2 * PANEL_INSET)
        row:SetPoint("TOPLEFT", PANEL_INSET, -64 - (index - 1) * ROW_HEIGHT)
        row:SetScript("OnClick", function(self)
            if not CanOperate() or self.setID == nil then
                return
            end
            if WSF.Equip(self.setID) then
                selection:Hide()
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.setName)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        rows[index] = row
    end

    selection.previous = CreateButton(selection, "<", 36)
    selection.previous:SetPoint("BOTTOMLEFT", GAP, GAP)
    selection.previous:SetScript("OnClick", function()
        page = math.max(1, page - 1)
        RenderPage()
    end)
    selection.next = CreateButton(selection, ">", 36)
    selection.next:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    selection.next:SetScript("OnClick", function()
        page = page + 1
        RenderPage()
    end)
    selection.pageText = PanelText(selection, "", true)
    selection.pageText:SetPoint("BOTTOM", 0, 14)
    selection:SetScript("OnHide", function()
        sets = {}
        for _, row in ipairs(rows) do
            row.setID = nil
            row.setName = nil
        end
        GameTooltip:Hide()
    end)
end

local function UpdateAvailability()
    if controls then
        local available = not not WSF.available
        for _, button in ipairs({controls.save, controls.equip}) do
            button:SetEnabled(available)
            button.icon:SetDesaturated(not available)
        end
    end
end

local function Initialize()
    if controls or not loggedIn or not PaperDollFrame or not CharacterFrame
        or not CharacterFrame.LeftPaneHost or not PaperDollFrame.ItemsFrame
        or not CharacterWristSlot or not CharacterTrinket1Slot
        or InCombatLockdown() then
        return
    end

    -- A mouse-transparent container lets parent hiding close every WSF control.
    controls = CreateFrame("Frame", nil, PaperDollFrame.ItemsFrame)
    controls:SetAllPoints(PaperDollFrame.ItemsFrame)
    -- Wrist and Trinket1 are the last slots in the left and right columns.
    controls.save = CreateIconButton(SAVE_ICON, CharacterWristSlot)
    controls.equip = CreateIconButton(EQUIP_ICON, CharacterTrinket1Slot)
    CreateSelection()
    CreateSaveDialog()

    controls.save:SetScript("OnClick", function()
        if not CanSave() then
            return
        end
        selection:Hide()
        saveDialog:Show()
    end)
    controls.equip:SetScript("OnClick", function()
        if selection:IsShown() then
            selection:Hide()
            return
        end
        if not CanOperate() then
            return
        end
        saveDialog:Hide()
        page = 1
        if RefreshSets() then
            selection:Show()
        end
    end)
    SetTooltip(controls.save, "WSF: Save weapons", "Save current weapons by name. An existing native set with that name is overwritten, regardless of creator.", true)
    SetTooltip(controls.equip, "WSF: Equip weapons", "Equip a weapon set outside combat. Use native /equipset macros in combat.")
    controls:SetScript("OnShow", UpdateAvailability)
    controls:SetScript("OnHide", function()
        selection:Hide()
        saveDialog:Hide()
        GameTooltip:Hide()
    end)
    UpdateAvailability()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Read availability after all core PLAYER_LOGIN handlers have run.
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                Initialize()
                UpdateAvailability()
            end)
        else
            Initialize()
            UpdateAvailability()
        end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        if saveDialog and saveDialog:IsShown() then
            saveDialog:Hide()
            WSF.Report(COMBAT_MESSAGE)
        end
        return
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        if selection and selection:IsShown() then
            RefreshSets()
        end
        return
    end
    Initialize()
    UpdateAvailability()
end)

Initialize()
