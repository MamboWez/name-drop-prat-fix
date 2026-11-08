-- Frames.lua: short names on unit frames (player, target, focus, party), raid frames and nameplates.
local _, ns = ...
local Names = ns.Names

local type, pairs, pcall, setmetatable = type, pairs, pcall, setmetatable
local strfind = string.find
local Readable, ReadableString = ns.Readable, ns.ReadableString

-- Every frame the game updated, so a settings change (or login) can restyle what is on screen now.
local seen = setmetatable({}, { __mode = "k" })

local function Wanted(kind)
	if not ns.active then
		return false
	end
	if kind == "plate" then
		return ns.settings.nameplates
	end
	return ns.settings.frames
end

local function CallIsForbidden(frame)
	return frame:IsForbidden()
end

local function IsForbidden(frame)
	local ok, forbidden = pcall(CallIsForbidden, frame)
	return not ok or not Readable(forbidden) or forbidden
end

-- True to leave the text alone: your own name follows the game's "My Secondary Name" option
-- (Options > Nameplates), and when the game won't say whether this unit is you, nothing is changed.
local function KeepOwnName(unit)
	if not (C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname) then
		return false
	end
	local ok, isMe = pcall(UnitIsUnit, unit, "player")
	if not ok or not Readable(isMe) then
		return true
	end
	if not isMe then
		return false
	end
	local okShow, show = pcall(C_PlayerInfo.ShouldDisplaySurname)
	return not (okShow and Readable(show) and show)
end

local function Apply(fontString, unit, restore)
	if type(fontString) ~= "table" or not fontString.GetText or type(unit) ~= "string" then
		return
	end
	local first, surname = ns.UnitNames(unit)
	if not first or KeepOwnName(unit) then
		return
	end
	local text = fontString:GetText()
	if not ReadableString(text) then
		return
	end
	ns.registry:Learn(first, surname)
	local target = restore and Names.Full(first, surname) or nil
	local new, changed = ns.registry:Swap(text, first, surname, target)
	if changed then
		fontString:SetText(new)
	end
end

local function ApplyUnitFrame(frame, restore)
	Apply(frame.name, frame.overrideName or frame.unit, restore)
end

local function ApplyCompact(frame, restore)
	Apply(frame.name, frame.unit, restore)
end

local function CompactKind(frame)
	local unit = frame.unit
	if type(unit) ~= "string" then
		return nil
	end
	return strfind(unit, "^nameplate") and "plate" or "compact"
end

local function OnUnitFrameUpdate(frame)
	if (ns.loggedIn and not ns.forever) or type(frame) ~= "table" or IsForbidden(frame) then
		return
	end
	seen[frame] = "unit"
	if Wanted("unit") then
		local ok, err = pcall(ApplyUnitFrame, frame, false)
		if not ok then
			ns.lastError = err
		end
	end
end

local function OnCompactUpdateName(frame)
	if (ns.loggedIn and not ns.forever) or type(frame) ~= "table" or IsForbidden(frame) then
		return
	end
	local ok, kind = pcall(CompactKind, frame)
	if not ok or not kind then
		return
	end
	seen[frame] = kind
	if Wanted(kind) then
		local applied, err = pcall(ApplyCompact, frame, false)
		if not applied then
			ns.lastError = err
		end
	end
end

-- Puts every frame on screen into the current style (or back to full names when that part is off).
function ns.RefreshFrames()
	if not ns.forever then
		return
	end
	for frame, kind in pairs(seen) do
		if not IsForbidden(frame) then
			local ok, err = pcall(kind == "unit" and ApplyUnitFrame or ApplyCompact, frame, not Wanted(kind))
			if not ok then
				ns.lastError = err
			end
		end
	end
end

ns.RegisterCallback("init", function()
	if type(UnitFrame_Update) == "function" then
		hooksecurefunc("UnitFrame_Update", OnUnitFrameUpdate)
	end
	if type(CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", OnCompactUpdateName)
	end
end)

ns.RegisterCallback("login", function()
	ns.RefreshFrames()
end)

ns.RegisterCallback("settings", function()
	ns.RefreshFrames()
end)
