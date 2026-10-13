local _, WSF = ...

local MAX_NAME_LETTERS = 16
local SAVE_USAGE = 'Use /wsf save Name or /wsf save "Set Name".'

function WSF.ValidateName(name)
    if type(name) ~= "string" or not name:find("%S") then
        return false, "Enter a non-empty set name."
    end
    if name:find("[%c|]") then
        return false, "Set names cannot contain control characters or |."
    end
    local _, letters = name:gsub("[^\128-\191]", "")
    if letters > MAX_NAME_LETTERS then
        return false, "Use a set name with at most 16 letters."
    end
    return true
end

function WSF.ParseSaveCommand(message)
    if type(message) ~= "string" then
        return nil, SAVE_USAGE
    end
    local command, arguments = message:match("^%s*(%S+)%s*(.-)%s*$")
    if not command or command:lower() ~= "save" or arguments == "" then
        return nil, SAVE_USAGE
    end

    local name
    if arguments:sub(1, 1) == '"' then
        name = arguments:match('^"([^"\r\n]*)"$')
    elseif not arguments:find('[%s"]') then
        name = arguments
    end
    if not name then
        return nil, SAVE_USAGE
    end
    local valid, messageText = WSF.ValidateName(name)
    if not valid then
        return nil, messageText
    end
    return name
end

function WSF.HandleCommand(message)
    local name, messageText = WSF.ParseSaveCommand(message)
    if not name then
        WSF.Report(messageText)
        return
    end
    local saved, saveError = WSF.Save(name)
    if saved then
        WSF.Report("Saved weapon set: " .. name)
    else
        WSF.Report(saveError)
    end
end
