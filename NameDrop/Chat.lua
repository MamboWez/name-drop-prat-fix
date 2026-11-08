-- Chat.lua: short names in chat. Only what is displayed changes: the player link behind each name keeps
-- the full name, so click (whisper), right-click (invite, ignore, report), shift-click and /r still work.
-- Lines already in chat are never rewritten afterwards (that would make faded lines reappear and confuse
-- chat addons that draw their own copy); hovering any name still shows who it is.
local _, ns = ...
local Names = ns.Names

local type, select, pcall, ipairs, tconcat = type, select, pcall, ipairs, table.concat
local strfind, strmatch = string.find, string.match
local IsSecret, ReadableString = ns.IsSecret, ns.ReadableString

-- Sender names --------------------------------------------------------------------------------------

local SKIP_EVENT_PREFIXES = { "CHAT_MSG_BN", "CHAT_MSG_MONSTER", "CHAT_MSG_RAID_BOSS" }

-- decorated: the sender name as the game will show it (class colour etc.); ...: the chat event's arguments.
function ns.ShortSender(event, decorated, ...)
	if not ReadableString(event) or not ReadableString(decorated) then
		return nil
	end
	for i = 1, #SKIP_EVENT_PREFIXES do
		if strfind(event, SKIP_EVENT_PREFIXES[i], 1, true) == 1 then
			return nil
		end
	end
	local sender, guid = select(2, ...), select(12, ...)
	if not ReadableString(sender) or IsSecret(guid) or strfind(decorated, "|K", 1, true) then
		return nil
	end
	if type(guid) == "string" and guid ~= "" and not strfind(guid, "^Player%-") then
		return nil
	end
	local first, surname = Names.Split(sender)
	if not surname then
		return nil
	end
	ns.registry:Learn(first, surname)
	ns.NoteClassByGUID(first, surname, guid)
	local new, changed = ns.registry:Swap(decorated, first, surname)
	if changed then
		return new
	end
	return nil
end

local function SenderNameFilter(event, decorated, ...)
	if not ns.active or not ns.settings.chat then
		return nil
	end
	local ok, result = pcall(ns.ShortSender, event, decorated, ...)
	if ok then
		return result
	end
	ns.lastError = result
	return nil
end

-- Names inside system, loot, roll and emote lines -----------------------------------------------------

local LINE_EVENTS = {
	"CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_OPENING", "CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_TARGETICONS", "CHAT_MSG_COMBAT_HONOR_GAIN",
	"CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE",
}

function ns.RewriteLine(chatFrame, event, msg, sender)
	if not ReadableString(msg) then
		return nil
	end
	-- Whisper windows match "player not found"/"came online" lines by their exact text.
	if event == "CHAT_MSG_SYSTEM" and type(chatFrame) == "table" and chatFrame.privateMessageList then
		return nil
	end
	local skip
	if event == "CHAT_MSG_TEXT_EMOTE" then
		-- The game turns the sender's name in the text into their link afterwards, so leave it alone.
		if not ReadableString(sender) then
			return nil
		end
		local first, surname = Names.Split(sender)
		skip = surname and Names.Full(first, surname) or sender
	end
	local new = ns.registry:RewriteMessage(msg, { links = true, plain = true, linkify = true, learn = true, skip = skip })
	if new ~= msg then
		return new
	end
	return nil
end

local function LineFilter(chatFrame, event, msg, sender, ...)
	if not ns.active or not ns.settings.system then
		return false
	end
	local ok, new = pcall(ns.RewriteLine, chatFrame, event, msg, sender)
	if not ok then
		ns.lastError = new
		return false
	end
	if new then
		return false, new, sender, ...
	end
	return false
end

-- Hover a name in chat to see who it is ----------------------------------------------------------------

local tooltipShown = false

function ns.ShowNameTooltip(owner, link)
	if not ReadableString(link) then
		return
	end
	local linkType, rest = strmatch(link, "^([^:]+):(.*)$")
	if linkType ~= "player" and linkType ~= "playerCommunity" then
		return
	end
	local first, surname = Names.Split(strmatch(rest, "^([^:]*)"))
	if not surname then
		return
	end
	local R = ns.registry
	local full = Names.Full(first, surname)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[ns.classOf[full] or ""]
	GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
	if color then
		GameTooltip:SetText(full, color.r, color.g, color.b)
	else
		GameTooltip:SetText(full, 1, 1, 1)
	end
	local short = R:Short(first, surname)
	if short ~= full then
		-- The current tag; an older line may still show the tag it was written with.
		GameTooltip:AddLine("Now shown as: " .. short, 0.8, 0.8, 0.8)
	end
	local nearest, others = R:Nearest(first, surname, 4)
	if others > 0 then
		local sample = {}
		for i, other in ipairs(nearest) do
			sample[i] = R:Short(first, other)
		end
		local more = others > #sample and ", ..." or ""
		GameTooltip:AddLine(("%d other %s you've seen: %s%s"):format(others, first, tconcat(sample, ", "), more), 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
	tooltipShown = true
end

local function OnLinkEnter(_, chatFrame, link)
	if not ns.active or not ns.settings.hover then
		return
	end
	local ok, err = pcall(ns.ShowNameTooltip, chatFrame, link)
	if not ok then
		ns.lastError = err
	end
end

local function OnLinkLeave()
	if tooltipShown then
		tooltipShown = false
		GameTooltip:Hide()
	end
end

-- Wiring ------------------------------------------------------------------------------------------------

ns.RegisterCallback("init", function()
	if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
		ChatFrameUtil.AddSenderNameFilter(SenderNameFilter)
	else
		ns.noSenderFilter = true
	end
	local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if addFilter then
		for _, event in ipairs(LINE_EVENTS) do
			addFilter(event, LineFilter)
		end
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", OnLinkEnter, ns)
		EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", OnLinkLeave, ns)
	end
end)
