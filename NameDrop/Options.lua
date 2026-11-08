-- Options.lua: the settings panel (Options > AddOns > Name Drop) and /namedrop commands.
local _, ns = ...
local Names = ns.Names

local type, ipairs, pairs, tostring, print, min = type, ipairs, pairs, tostring, print, math.min
local strlower, strmatch, format, tsort = string.lower, string.match, string.format, table.sort

ns.MODE_LABELS = {
	smart = "Smart - Frost W. (adds letters only when two people would look alike)",
	auto = "Minimal - Frost (a letter appears only once you've met two Frosts)",
	initial = "Initial - Frost W. (always one letter)",
	first = "First name only - Frost",
	full = "Full name - Frost Winterborn (game default)",
}

local TOGGLES = {
	{ key = "enabled", label = "Enable Name Drop", tip = "Turn every Name Drop change on or off." },
	{ key = "chat", label = "Chat: speaker names", tip = "[Frost W.]: hello - in say, party, guild, whispers, channels and emotes." },
	{ key = "system", label = "Chat: system, loot and roll lines", tip = "Frost W. rolls 42 (1-100), Frost W. receives loot, joins/leaves." },
	{ key = "frames", label = "Unit frames", tip = "Player, target, focus, party and raid frames." },
	{ key = "nameplates", label = "Nameplates", tip = "Names on nameplates (when nameplates are shown)." },
	{ key = "hover", label = "Hover a name in chat to see the full name", tip = "Also lists the other people with that first name you've seen." },
}
local TOGGLE_KEYS = { plates = "nameplates" }
for _, t in ipairs(TOGGLES) do
	TOGGLE_KEYS[t.key] = t.key
end

-- Settings panel -----------------------------------------------------------------------------------------

local settingObjects = {}

local function ModeOptions()
	local container = Settings.CreateControlTextContainer()
	for _, mode in ipairs(ns.MODES) do
		container:Add(mode, ns.MODE_LABELS[mode])
	end
	return container:GetData()
end

local function BuildPanel()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end
	local varType = Settings.VarType or { Boolean = "boolean", String = "string" }
	local category = Settings.RegisterVerticalLayoutCategory("Name Drop")
	local function OnChanged()
		ns.SettingsChanged()
	end

	local mode = Settings.RegisterAddOnSetting(category, "NAMEDROP_MODE", "mode", ns.settings, varType.String, "Name style", ns.DEFAULTS.mode)
	mode:SetValueChangedCallback(OnChanged)
	Settings.CreateDropdown(category, mode, ModeOptions, "How other players' names are written. Hovering a name in chat always shows the full name.")
	settingObjects.mode = mode

	for _, t in ipairs(TOGGLES) do
		local setting = Settings.RegisterAddOnSetting(category, "NAMEDROP_" .. t.key:upper(), t.key, ns.settings, varType.Boolean, t.label, ns.DEFAULTS[t.key])
		setting:SetValueChangedCallback(OnChanged)
		Settings.CreateCheckbox(category, setting, t.tip)
		settingObjects[t.key] = setting
	end

	Settings.RegisterAddOnCategory(category)
	ns.category = category
end

function ns.OpenSettings()
	if ns.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.category:GetID())
		return true
	end
	return false
end

-- Changes a setting the same way the panel does, so the panel stays in sync.
function ns.SetOption(key, value)
	local before = ns.changeCount
	local setting = settingObjects[key]
	if setting then
		setting:SetValue(value)
	end
	if ns.settings[key] ~= value then
		ns.settings[key] = value
	end
	if ns.changeCount == before then
		ns.SettingsChanged()
	end
end

-- Slash commands ---------------------------------------------------------------------------------------------

local function OnOff(value)
	return value and "|cff33ff33on|r" or "|cffff5555off|r"
end

local function Help()
	ns.Print("version " .. ns.VERSION .. (ns.active and "" or " |cffff5555(inactive)|r"))
	print("  /namedrop - open the settings")
	print("  /namedrop mode smart | auto | initial | first | full - name style (now: " .. ns.settings.mode .. ")")
	print("  /namedrop who <first name> - everyone with that first name you've seen")
	print("  /namedrop test - preview the current style")
	print("  /namedrop on | off - enable or disable everything")
	print("  /namedrop chat | system | frames | plates | hover [on|off] - toggle a part")
	print("  /namedrop stats - how many people Name Drop knows")
	print("  /namedrop forget - forget everyone seen so far")
end

local function PlayerLink(full)
	return "|Hplayer:" .. full .. "|h[" .. full .. "]|h"
end

local function Who(typed)
	local R = ns.registry
	local first = R:FindFirst(typed)
	if not first then
		ns.Print(format("no one called %s seen yet.", tostring(typed)))
		return
	end
	local list = R:Surnames(first)
	ns.Print(format("%d %s known (click a name to whisper):", #list, first))
	for i = 1, min(#list, 30) do
		print(format("  %s  =  %s", R:Short(first, list[i]), PlayerLink(Names.Full(first, list[i]))))
	end
	if #list > 30 then
		print(format("  ... and %d more", #list - 30))
	end
end

local PREVIEW = {
	{ "Frost", "Winterborn" }, { "Frost", "Wildheart" }, { "Frost", "Blackwood" },
	{ "Asha", "Brightvale" }, { "Thalen", "Brightvale" },
}

local function Preview()
	local R = Names.NewRegistry({}, { mode = ns.settings.mode })
	for _, p in ipairs(PREVIEW) do
		R:Learn(p[1], p[2])
	end
	ns.Print("preview - " .. ns.MODE_LABELS[ns.settings.mode])
	for _, p in ipairs(PREVIEW) do
		print(format("  %s  ->  |cffffd100%s|r", Names.Full(p[1], p[2]), R:Short(p[1], p[2])))
	end
end

local function Stats()
	local people, firsts = ns.registry:Count()
	ns.Print(format("knows %d people with %d different first names.", people, firsts))
	local top = {}
	for first, set in pairs(ns.registry.known) do
		local n = 0
		for _ in pairs(set) do
			n = n + 1
		end
		if n > 1 then
			top[#top + 1] = { first, n }
		end
	end
	tsort(top, function(a, b) return a[2] > b[2] end)
	for i = 1, min(#top, 5) do
		print(format("  %s: %d people", top[i][1], top[i][2]))
	end
end

local function Status()
	local parts = {}
	for _, t in ipairs(TOGGLES) do
		parts[#parts + 1] = t.key .. " " .. OnOff(ns.settings[t.key])
	end
	ns.Print("mode " .. ns.settings.mode .. " - " .. table.concat(parts, ", "))
end

function ns.HandleCommand(msg)
	local cmd, rest = strmatch(msg or "", "^%s*(%S*)%s*(.-)%s*$")
	cmd = strlower(cmd or "")
	local arg = strlower(rest or "")
	if cmd == "" then
		if not ns.OpenSettings() then
			Help()
		end
	elseif cmd == "help" or cmd == "?" then
		Help()
	elseif cmd == "mode" or ns.VALID_MODE[cmd] then
		local mode = ns.VALID_MODE[cmd] and cmd or arg
		if ns.VALID_MODE[mode] then
			ns.SetOption("mode", mode)
			ns.Print("name style: " .. ns.MODE_LABELS[mode])
		else
			ns.Print("mode is " .. ns.settings.mode .. ". Choose: smart, auto, initial, first or full.")
		end
	elseif cmd == "on" or cmd == "off" then
		ns.SetOption("enabled", cmd == "on")
		ns.Print("Name Drop " .. OnOff(ns.settings.enabled))
	elseif TOGGLE_KEYS[cmd] then
		local key = TOGGLE_KEYS[cmd]
		local value
		if arg == "on" then
			value = true
		elseif arg == "off" then
			value = false
		else
			value = not ns.settings[key]
		end
		ns.SetOption(key, value)
		ns.Print(key .. " " .. OnOff(ns.settings[key]))
	elseif cmd == "who" then
		if rest == "" then
			ns.Print("usage: /namedrop who <first name>")
		else
			Who(rest)
		end
	elseif cmd == "test" or cmd == "preview" then
		Preview()
	elseif cmd == "stats" then
		Stats()
	elseif cmd == "status" then
		Status()
	elseif cmd == "forget" then
		if arg == "confirm" then
			ns.registry:Forget()
			ns.Print("forgot everyone.")
		else
			ns.Print("this forgets every name Name Drop has seen. Type /namedrop forget confirm to do it.")
		end
	elseif cmd == "debug" then
		ns.Print(format("forever=%s active=%s separator=%q senderFilter=%s pratCompat=%s lastError=%s", tostring(ns.forever),
			tostring(ns.active), Names.SEP, tostring(not ns.noSenderFilter), tostring(ns.pratCompatInstalled == true), tostring(ns.lastError)))
	else
		Help()
	end
end

SLASH_NAMEDROP1 = "/namedrop"
SLASH_NAMEDROP2 = "/nd"
SlashCmdList.NAMEDROP = function(msg)
	ns.HandleCommand(msg)
end

ns.RegisterCallback("init", BuildPanel)
