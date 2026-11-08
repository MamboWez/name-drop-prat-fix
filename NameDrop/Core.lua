-- Core.lua: saved variables, activation, and learning who is who (chat, group, guild, friends, /who, target).
local addonName, ns = ...
local Names = ns.Names

local type, pairs, ipairs, pcall, print, tostring = type, pairs, ipairs, pcall, print, tostring
local issecretvalue, canaccessvalue = issecretvalue, canaccessvalue

-- The version lives in NameDrop.toc only (the CurseForge upload reads it from there too).
local function TocVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if type(get) == "function" then
		local ok, version = pcall(get, addonName, "Version")
		if ok and type(version) == "string" and version ~= "" then
			return version
		end
	end
	return "dev"
end

ns.VERSION = TocVersion()
ns.DEFAULTS = {
	enabled = true,
	mode = "smart",
	chat = true,
	system = true,
	frames = true,
	nameplates = true,
	hover = true,
	keepDays = 90,
}
ns.MODES = { "smart", "auto", "initial", "first", "full" }
ns.VALID_MODE = { smart = true, auto = true, initial = true, first = true, full = true }
ns.MAX_KNOWN = 40000

ns.active = false
ns.forever = false
ns.classOf = {}
ns.changeCount = 0

local callbacks = { init = {}, login = {}, settings = {} }

function ns.RegisterCallback(kind, fn)
	local list = callbacks[kind]
	list[#list + 1] = fn
end

local function Run(kind)
	for _, fn in ipairs(callbacks[kind]) do
		local ok, err = pcall(fn)
		if not ok then
			ns.lastError = err
		end
	end
end

-- True for values the game hides from addons (secret values in instances/combat). Checked before anything
-- else touches a value: comparing or concatenating a secret value is an error.
function ns.IsSecret(v)
	if issecretvalue and issecretvalue(v) then
		return true
	end
	return canaccessvalue ~= nil and not canaccessvalue(v)
end

-- False for nil and for secret values.
function ns.Readable(v)
	if ns.IsSecret(v) then
		return false
	end
	return v ~= nil
end
local Readable = ns.Readable

local function ReadableString(v)
	return Readable(v) and type(v) == "string" and v ~= ""
end
ns.ReadableString = ReadableString

function ns.Print(msg)
	print("|cff66bbffName Drop|r: " .. tostring(msg))
end

function ns.IsForever()
	if type(RegionalUniqueNamesEnabled) == "function" then
		local ok, on = pcall(RegionalUniqueNamesEnabled)
		if ok and Readable(on) then
			return on and true or false
		end
	end
	return C_PlayerInfo ~= nil and C_PlayerInfo.ShouldDisplaySurname ~= nil
end

function ns.UpdateActive()
	ns.active = ns.forever and ns.settings ~= nil and ns.settings.enabled ~= false
end

function ns.SettingsChanged()
	ns.changeCount = ns.changeCount + 1
	if not ns.VALID_MODE[ns.settings.mode] then
		ns.settings.mode = ns.DEFAULTS.mode
	end
	ns.registry:Invalidate()
	ns.UpdateActive()
	Run("settings")
end

-- Learning -------------------------------------------------------------------------------------

local function NoteClass(first, surname, classFile)
	if ReadableString(classFile) then
		ns.classOf[Names.Full(first, surname)] = classFile
	end
end

function ns.NoteClassByGUID(first, surname, guid)
	local full = Names.Full(first, surname)
	if ns.classOf[full] or type(GetPlayerInfoByGUID) ~= "function" or not ReadableString(guid) then
		return
	end
	local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
	if ok then
		NoteClass(first, surname, classFile)
	end
end

function ns.LearnName(name, classFile)
	if not ReadableString(name) then
		return nil
	end
	local first, surname = Names.Split(name)
	if not surname then
		return nil
	end
	ns.registry:Learn(first, surname)
	NoteClass(first, surname, classFile)
	return first, surname
end

-- First name and surname of a player unit; nil for NPCs, unknown units and hidden (secret) names.
-- Forever's UnitName returns (first, surname); older beta builds returned ("First Surname", realm).
function ns.UnitNames(unit)
	if type(unit) ~= "string" or unit == "" then
		return nil
	end
	local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
	if not okPlayer or not Readable(isPlayer) or not isPlayer then
		return nil
	end
	local ok, a, b = pcall(UnitName, unit)
	if not ok or not ReadableString(a) then
		return nil
	end
	local first, surname = Names.Split(a)
	if surname then
		return first, surname
	end
	if ReadableString(b) then
		return a, b
	end
	-- Probed on build 70009: UnitName("player") gave only the first name, UnitFullName the surname too.
	if type(UnitFullName) == "function" then
		local okFull, c, d = pcall(UnitFullName, unit)
		if okFull and ReadableString(c) and ReadableString(d) and c == a then
			return c, d
		end
	end
	return nil
end

function ns.LearnUnit(unit)
	local first, surname = ns.UnitNames(unit)
	if not first then
		return nil
	end
	ns.registry:Learn(first, surname)
	local ok, _, classFile = pcall(UnitClass, unit)
	if ok then
		NoteClass(first, surname, classFile)
	end
	return first, surname
end

local function Yes(fn)
	if type(fn) ~= "function" then
		return false
	end
	local ok, value = pcall(fn)
	return ok and Readable(value) and value == true
end

local function ScanGroup()
	if Yes(IsInRaid) then
		for i = 1, 40 do
			ns.LearnUnit("raid" .. i)
		end
	else
		for i = 1, 4 do
			ns.LearnUnit("party" .. i)
		end
	end
	ns.LearnUnit("player")
end

local function ScanGuild()
	if not (Yes(IsInGuild) and GetNumGuildMembers and GetGuildRosterInfo) then
		return
	end
	local total = GetNumGuildMembers()
	if not Readable(total) or type(total) ~= "number" then
		return
	end
	for i = 1, total do
		local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
		ns.LearnName(name, classFile)
	end
end

local function ScanFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
		return
	end
	local total = C_FriendList.GetNumFriends()
	if not Readable(total) or type(total) ~= "number" then
		return
	end
	for i = 1, total do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if type(info) == "table" then
			ns.LearnName(info.name)
		end
	end
end

local function ScanWho()
	if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then
		return
	end
	local total = C_FriendList.GetNumWhoResults()
	if not Readable(total) or type(total) ~= "number" then
		return
	end
	for i = 1, total do
		local info = C_FriendList.GetWhoInfo(i)
		if type(info) == "table" then
			ns.LearnName(info.fullName, info.filename)
		end
	end
end

local queued = {}
local function Soon(key, delay, fn)
	if queued[key] then
		return
	end
	queued[key] = true
	C_Timer.After(delay, function()
		queued[key] = nil
		local ok, err = pcall(fn)
		if not ok then
			ns.lastError = err
		end
	end)
end

local LEARN_EVENTS = {
	GROUP_ROSTER_UPDATE = function() Soon("group", 1, ScanGroup) end,
	GUILD_ROSTER_UPDATE = function() Soon("guild", 10, ScanGuild) end,
	FRIENDLIST_UPDATE = function() Soon("friends", 2, ScanFriends) end,
	WHO_LIST_UPDATE = function() Soon("who", 0.5, ScanWho) end,
	PLAYER_TARGET_CHANGED = function() ns.LearnUnit("target") end,
	PLAYER_FOCUS_CHANGED = function() ns.LearnUnit("focus") end,
	UPDATE_MOUSEOVER_UNIT = function() ns.LearnUnit("mouseover") end,
}

-- Startup ----------------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function OnAddonLoaded()
	local db = type(NameDropDB) == "table" and NameDropDB or {}
	NameDropDB = db
	if type(db.settings) ~= "table" then
		db.settings = {}
	end
	if type(db.known) ~= "table" then
		db.known = {}
	end
	for key, value in pairs(ns.DEFAULTS) do
		if type(db.settings[key]) ~= type(value) then
			db.settings[key] = value
		end
	end
	if not ns.VALID_MODE[db.settings.mode] then
		db.settings.mode = ns.DEFAULTS.mode
	end
	db.version = ns.VERSION
	ns.db = db
	ns.settings = db.settings
	ns.registry = Names.NewRegistry(db.known, db.settings)
	ns.registry:Prune(db.settings.keepDays, ns.MAX_KNOWN)
	-- Keep the saved list bounded during long sessions too (busy cities and channels).
	ns.registry.cap = ns.MAX_KNOWN + 2000
	ns.registry.onOverflow = function()
		Soon("prune", 5, function()
			ns.registry:Prune(ns.settings.keepDays, ns.MAX_KNOWN)
		end)
	end
	Run("init")
end

local function OnLogin()
	ns.loggedIn = true
	Names.RefreshSeparator()
	ns.forever = ns.IsForever()
	ns.UpdateActive()
	if not ns.forever then
		ns.Print("this game version does not use first + last names, so Name Drop stays idle.")
		return
	end
	for event in pairs(LEARN_EVENTS) do
		events:RegisterEvent(event)
	end
	for _, scan in ipairs({ function() ns.LearnUnit("player") end, ScanGroup, ScanFriends }) do
		local ok, err = pcall(scan)
		if not ok then
			ns.lastError = err
		end
	end
	if Yes(IsInGuild) and C_GuildInfo and C_GuildInfo.GuildRoster then
		pcall(C_GuildInfo.GuildRoster)
	end
	Run("login")
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			events:UnregisterEvent("ADDON_LOADED")
			OnAddonLoaded()
		end
	elseif event == "PLAYER_LOGIN" then
		OnLogin()
	else
		local handler = LEARN_EVENTS[event]
		if handler then
			local ok, err = pcall(handler, ...)
			if not ok then
				ns.lastError = err
			end
		end
	end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
