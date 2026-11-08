-- PratCompat.lua: keep Name Drop's chat speaker shortening when Prat builds chat lines.
-- Prat uses its own ChatFrame_MessageEventHandler and message sections; its PLAYER section
-- needs to be updated before Prat joins the sections into the final chat line.
-- We deliberately leave PLAYERLINK and every |Hplayer:...|h target untouched.
local _, ns = ...
local Names = ns.Names
local ReadableString = ns.ReadableString
local type, pcall = type, pcall
local strfind, strmatch = string.find, string.match

local function LearnFrom(candidate)
    if not ReadableString(candidate) then
        return
    end
    -- A Prat player section can contain an ordinary full name or a player hyperlink.
    -- Never change the hyperlink's actual destination.
    local linkName = strmatch(candidate, "|Hplayer[^:]*:([^:|]+)")
    -- Avoid feeding Prat's colour/bracket markup to the name registry as if it
    -- were part of a real character name.
    if not linkName and (strfind(candidate, "|", 1, true) or
                         strfind(candidate, "[", 1, true) or
                         strfind(candidate, "]", 1, true)) then
        return
    end
    local first, surname = Names.Split(linkName or candidate)
    if surname then
        ns.registry:Learn(first, surname)
    end
end

-- This is a testable helper and is called only for Prat's own message table.
function ns.ShortenPratMessage(m, chatEvent)
    if not ns.active or not ns.settings.chat or type(m) ~= "table" then
        return false
    end
    if ReadableString(chatEvent) and
       (strfind(chatEvent, "CHAT_MSG_BN", 1, true) == 1 or
        strfind(chatEvent, "CHAT_MSG_MONSTER", 1, true) == 1 or
        strfind(chatEvent, "CHAT_MSG_RAID_BOSS", 1, true) == 1) then
        return false
    end

    local player = m.PLAYER
    if not ReadableString(player) then
        return false
    end
    -- When Prat has a separate player-link/name field, learn the FULL name first.
    -- Otherwise, the registry also learns from |Hplayer:...|h links in PLAYER below.
    LearnFrom(m.PLAYERLINK)
    LearnFrom(player)

    local short = ns.registry:RewriteMessage(player, {
        links = true, plain = true, linkify = false, learn = true
    })
    if short ~= player then
        m.PLAYER = short
        return true
    end
    return false
end

local function OnPratPreAddMessage(eventName, m, frame, chatEvent)
    if not ns.active or not ns.settings.chat then
        return
    end
    local ok, err = pcall(ns.ShortenPratMessage, m, chatEvent)
    if not ok then
        ns.lastError = err
    end
end

local installed = false
local function InstallPratIntegration()
    if installed then
        return
    end
    local prat = _G.Prat
    if type(prat) ~= "table" or type(prat.RegisterChatEvent) ~= "function" then
        return
    end
    -- CallbackHandler-1.0: ns owns this callback; it is not a Prat module.
    local ok, err = pcall(prat.RegisterChatEvent, ns, "Prat_PreAddMessage", OnPratPreAddMessage)
    if ok then
        installed = true
        ns.pratCompatInstalled = true
    else
        ns.lastError = err
    end
end

ns.RegisterCallback("init", InstallPratIntegration)
ns.RegisterCallback("login", InstallPratIntegration)
