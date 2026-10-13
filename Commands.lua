local _, WSF = ...

local MAX_NAME_LETTERS = 16
local SAVE_USAGE = 'Use /wsf save Name or /wsf save "Set Name".'
-- "export" is the user-facing name; "debug_probe" is the original diagnostic alias.
local PROBE_COMMANDS = {export = true, debug_probe = true}
local PROBE_USAGE = 'Use /wsf %s, /wsf %s Name, or /wsf %s "Set Name".'

local SWAP_DEBUG_COMMAND = "debug_swap"
local SWAP_DEBUG_USAGE = "Use /wsf debug_swap, /wsf debug_swap on, /wsf debug_swap off, or /wsf debug_swap status."

local function ProbeUsage(command)
    return PROBE_USAGE:format(command, command, command)
end

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

local function SplitCommand(message)
    if type(message) ~= "string" then
        return nil
    end
    local command, arguments = message:match("^%s*(%S+)%s*(.-)%s*$")
    if not command then
        return nil
    end
    return command:lower(), arguments
end

-- Exactly one argument: a bare word or one double-quoted name.
local function ParseNameArgument(arguments)
    if arguments:sub(1, 1) == '"' then
        return arguments:match('^"([^"\r\n]*)"$')
    elseif arguments ~= "" and not arguments:find('[%s"]') then
        return arguments
    end
end

function WSF.ParseSaveCommand(message)
    local command, arguments = SplitCommand(message)
    if command ~= "save" then
        return nil, SAVE_USAGE
    end
    local name = ParseNameArgument(arguments)
    if not name then
        return nil, SAVE_USAGE
    end
    local valid, messageText = WSF.ValidateName(name)
    if not valid then
        return nil, messageText
    end
    return name
end

-- Returns true plus an optional name; no argument means the equipped set or gear.
-- The probe is read-only, so it accepts any existing native set name.
function WSF.ParseProbeCommand(message)
    local command, arguments = SplitCommand(message)
    if not PROBE_COMMANDS[command] then
        return nil, ProbeUsage("export")
    end
    if arguments == "" then
        return true, nil
    end
    local name = ParseNameArgument(arguments)
    if not name or not name:find("%S") then
        return nil, ProbeUsage(command)
    end
    return true, name
end

-- Output lines repeat the command word the user typed.
local function HandleProbe(command, message)
    local valid, nameOrError = WSF.ParseProbeCommand(message)
    if not valid then
        WSF.Report(nameOrError)
        return
    end
    local probes, probeError
    if nameOrError then
        local json
        json, probeError = WSF.ProbeSet(nameOrError)
        probes = json and {json}
    else
        probes, probeError = WSF.ProbeEquipped()
    end
    if not probes then
        WSF.Report(probeError)
        return
    end
    for _, json in ipairs(probes) do
        WSF.Report(command .. " " .. json)
    end
end

-- Returns true, false, or nil for toggle; nil plus usage when malformed.
function WSF.ParseSwapDebugCommand(message)
    local command, arguments = SplitCommand(message)
    if command ~= SWAP_DEBUG_COMMAND then
        return nil, SWAP_DEBUG_USAGE
    end
    local setting = arguments:lower()
    if setting == "" then
        return true, nil
    elseif setting == "on" or setting == "off" then
        return true, setting == "on"
    elseif setting == "status" then
        return true, "status"
    end
    return nil, SWAP_DEBUG_USAGE
end

local function HandleSwapDebug(message)
    local valid, setting = WSF.ParseSwapDebugCommand(message)
    if not valid then
        WSF.Report(setting)
        return
    end
    if setting == "status" then
        WSF.ReportSwapDebugStatus()
        return
    end
    if not WSF.available then
        WSF.Report("Weapon sets are unavailable. Check the WSF login message.")
        return
    end
    if setting == nil then
        setting = not WSF.IsSwapDebugEnabled()
    end
    if WSF.SetSwapDebug(setting) then
        WSF.Report("debug_swap on: swap details print to chat until /wsf debug_swap off or /reload.")
    else
        WSF.Report("debug_swap off.")
    end
end

function WSF.HandleCommand(message)
    local command = SplitCommand(message)
    if PROBE_COMMANDS[command] then
        HandleProbe(command, message)
        return
    end
    if command == SWAP_DEBUG_COMMAND then
        HandleSwapDebug(message)
        return
    end
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
