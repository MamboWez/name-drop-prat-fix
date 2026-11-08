-- Names.lua: pure name logic (no frames, no events), so it can be tested outside the game.
local _, ns = ...

local Names = {}
ns.Names = Names

local type, pairs, next, setmetatable = type, pairs, next, setmetatable
local floor, min, max = math.floor, math.min, math.max
local strfind, strsub, strmatch, strbyte, gmatch, gsub = string.find, string.sub, string.match, string.byte, string.gmatch, string.gsub
local tconcat, tsort, tinsert = table.concat, table.sort, table.insert

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local WORD = "()([%a\128-\255]+)()"
local PIPE = 124

-- Blizzard joins "First" and "Surname" with this (a space on Forever); links and /who use "-".
Names.SEP = " "

function Names.RefreshSeparator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
	if type(sep) == "string" and sep ~= "" then
		Names.SEP = sep
	end
end
Names.RefreshSeparator()

function Names.Today()
	local now = (type(time) == "function" and time()) or (os and os.time and os.time()) or 0
	return floor(now / 86400)
end

-- A-Z only: string.lower follows the system locale, which can mangle the bytes of accented UTF-8 letters.
local ASCII_LOWER = {}
for c = 65, 90 do
	ASCII_LOWER[string.char(c)] = string.char(c + 32)
end
local function Lower(s)
	return (gsub(s, "[A-Z]", ASCII_LOWER))
end
Names.Lower = Lower

local function Chars(s)
	local t, n = {}, 0
	for c in gmatch(s, UTF8_CHAR) do
		n = n + 1
		t[n] = c
	end
	return t, n
end
Names.Chars = Chars

function Names.Prefix(s, count)
	local t, n = Chars(s)
	if count >= n then
		return s
	end
	return tconcat(t, "", 1, count)
end

-- "Frost Winterborn", "Frost-Winterborn" or "Frost Winterborn-Suffix" -> "Frost", "Winterborn", suffix.
-- Anything else (one word, three words, empty) -> the input and no surname.
function Names.Split(full)
	if type(full) ~= "string" or full == "" then
		return nil
	end
	local sep = Names.SEP
	local cut, width = strfind(full, sep, 1, true), #sep
	local dash = strfind(full, "-", 1, true)
	if not cut or (dash and dash < cut) then
		cut, width = dash, 1
	end
	if not cut then
		return full
	end
	local first, rest = strsub(full, 1, cut - 1), strsub(full, cut + width)
	local suffix
	local d = strfind(rest, "-", 1, true)
	if d then
		suffix = strsub(rest, d + 1)
		rest = strsub(rest, 1, d - 1)
	end
	if first == "" or rest == "" or strfind(rest, sep, 1, true) or strfind(first, " ", 1, true) then
		return full
	end
	return first, rest, (suffix ~= "" and suffix or nil)
end

function Names.Full(first, surname)
	if type(surname) ~= "string" or surname == "" then
		return first
	end
	return first .. Names.SEP .. surname
end

local function IsWordByte(b)
	return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 128)
end

-- True when position a starts a word: not glued to a letter, unless that letter ends an escape (|r, |t, |cffxxxxxx).
local function StartsWord(text, a)
	if a <= 1 or not IsWordByte(strbyte(text, a - 1)) then
		return true
	end
	if a > 2 and strbyte(text, a - 2) == PIPE then
		return true
	end
	return a > 10 and strfind(strsub(text, a - 10, a - 1), "^|c%x%x%x%x%x%x%x%x$") ~= nil
end

local function FindName(text, needle, needsTailBoundary)
	local pos = 1
	while true do
		local a, b = strfind(text, needle, pos, true)
		if not a then
			return nil
		end
		if StartsWord(text, a) and (not needsTailBoundary or not IsWordByte(strbyte(text, b + 1))) then
			return a, b
		end
		pos = a + 1
	end
end
Names.FindName = FindName

-- Byte order, the same whatever the client's locale is.
local function ByteLess(a, b)
	local la, lb = #a, #b
	for i = 1, (la < lb and la or lb) do
		local x, y = strbyte(a, i), strbyte(b, i)
		if x ~= y then
			return x < y
		end
	end
	return la < lb
end

-- First position in sorted keys whose key is not below key.
local function LowerBound(keys, key)
	local lo, hi = 1, #keys + 1
	while lo < hi do
		local mid = floor((lo + hi) / 2)
		if ByteLess(keys[mid], key) then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return lo
end

-- Positions of the nearest keys below and above key that differ from it.
local function Around(keys, key)
	local pos = LowerBound(keys, key)
	local after = pos
	while keys[after] == key do
		after = after + 1
	end
	return pos - 1, after
end

-- How many whole UTF-8 letters a and b start with in common.
local function CommonLetters(a, b)
	local n, i = min(#a, #b), 1
	while i <= n and strbyte(a, i) == strbyte(b, i) do
		i = i + 1
	end
	local bytes, letters, j = i - 1, 0, 1
	while j <= bytes do
		local c = strbyte(a, j)
		local width = (c < 192 and 1) or (c < 224 and 2) or (c < 240 and 3) or 4
		if j + width - 1 > bytes then
			break
		end
		letters = letters + 1
		j = j + width
	end
	return letters
end

local function LetterCount(s)
	local _, n = gsub(s, "[^\128-\191]", "")
	return n
end

local function CountKnown(known)
	local n = 0
	for _, set in pairs(known) do
		for _ in pairs(set) do
			n = n + 1
		end
	end
	return n
end

-- Registry: the people you have seen, known[first][surname] = day last seen.
-- index[first] keeps that first name's surnames sorted (case-insensitively): the tag a surname needs depends
-- only on its two alphabetical neighbours, so lookups stay fast even with thousands of people called Frost.
local Registry = {}
Registry.__index = Registry
local EMPTY_INDEX = { keys = {}, names = {} }

function Names.NewRegistry(known, settings)
	known = known or {}
	return setmetatable({ known = known, settings = settings or {}, cache = {}, index = {}, size = CountKnown(known) }, Registry)
end

function Registry:Mode()
	local s = self.settings
	if s.enabled == false then
		return "full"
	end
	return s.mode or "smart"
end

-- Forgets the display strings worked out so far (all, or one first name's), e.g. after a style change.
function Registry:Invalidate(first)
	if first then
		self.cache[first] = nil
	else
		self.cache = {}
	end
end

-- Rebuilds everything derived from known, after people were removed.
function Registry:Reindex()
	self.index = {}
	self.cache = {}
	self.size = CountKnown(self.known)
end

function Registry:Index(first)
	local idx = self.index[first]
	if idx then
		return idx
	end
	local set = self.known[first]
	if not set then
		return EMPTY_INDEX
	end
	local names, keyOf = {}, {}
	for surname in pairs(set) do
		names[#names + 1] = surname
		keyOf[surname] = Lower(surname)
	end
	tsort(names, function(a, b)
		return ByteLess(keyOf[a], keyOf[b])
	end)
	local keys = {}
	for i = 1, #names do
		keys[i] = keyOf[names[i]]
	end
	idx = { keys = keys, names = names }
	self.index[first] = idx
	return idx
end

-- A new surname changes only its own tag and its two alphabetical neighbours' tags.
function Registry:Inserted(first, surname)
	local idx = self.index[first]
	if not idx then
		self.cache[first] = nil
		return
	end
	local key = Lower(surname)
	local pos = LowerBound(idx.keys, key)
	tinsert(idx.keys, pos, key)
	tinsert(idx.names, pos, surname)
	local cached = self.cache[first]
	if cached then
		cached[surname] = nil
		local before, after = Around(idx.keys, key)
		if idx.names[before] then
			cached[idx.names[before]] = nil
		end
		if idx.names[after] then
			cached[idx.names[after]] = nil
		end
	end
end

-- Returns isNew, shared (shared: someone else already had this first name).
function Registry:Learn(first, surname, day)
	if type(first) ~= "string" or type(surname) ~= "string" or first == "" or surname == "" then
		return false, false
	end
	local set = self.known[first]
	if not set then
		set = {}
		self.known[first] = set
	end
	local isNew = set[surname] == nil
	local shared = isNew and next(set) ~= nil
	set[surname] = day or Names.Today()
	if isNew then
		self.size = self.size + 1
		self:Inserted(first, surname)
		if self.cap and self.size > self.cap and self.onOverflow then
			self.onOverflow()
		end
	end
	return isNew, shared
end

function Registry:Has(first, surname)
	local set = self.known[first]
	return set ~= nil and set[surname] ~= nil
end

-- Returns people, first names.
function Registry:Count()
	local firsts = 0
	for _ in pairs(self.known) do
		firsts = firsts + 1
	end
	return self.size, firsts
end

-- That first name's surnames, sorted alphabetically.
function Registry:Surnames(first)
	local names, list = self:Index(first).names, {}
	for i = 1, #names do
		list[i] = names[i]
	end
	return list
end

-- Up to limit other surnames closest to this one alphabetically (the likeliest mix-ups) and how many others there are.
function Registry:Nearest(first, surname, limit)
	local idx = self:Index(first)
	local keys, names = idx.keys, idx.names
	local before, after = Around(keys, Lower(surname))
	local others = #keys - (after - before - 1)
	local list, b, a = {}, before, after
	while #list < limit and (b >= 1 or a <= #names) do
		if b >= 1 then
			list[#list + 1] = names[b]
			b = b - 1
		end
		if #list < limit and a <= #names then
			list[#list + 1] = names[a]
			a = a + 1
		end
	end
	return list, others
end

-- Case-insensitive lookup of a first name as typed by the user.
function Registry:FindFirst(typed)
	if type(typed) ~= "string" or typed == "" then
		return nil
	end
	if self.known[typed] then
		return typed
	end
	local lower = Lower(typed)
	for first in pairs(self.known) do
		if Lower(first) == lower then
			return first
		end
	end
	return nil
end

-- How many surname letters keep this person apart from everyone else known with the same first name.
function Registry:LettersNeeded(first, surname, minLetters)
	local own = Lower(surname)
	local total = LetterCount(own)
	local keys = self:Index(first).keys
	local before, after = Around(keys, own)
	local need = minLetters
	local b, a = keys[before], keys[after]
	if b then
		need = max(need, CommonLetters(own, b) + 1)
	end
	if a then
		need = max(need, CommonLetters(own, a) + 1)
	end
	if need > total then
		need = total
	end
	return need, total
end

-- The name as Name Drop shows it: "Frost W.", "Frost Win.", "Frost" or "Frost Winterborn" depending on mode.
function Registry:Short(first, surname)
	if type(surname) ~= "string" or surname == "" then
		return first
	end
	local mode = self:Mode()
	if mode == "full" then
		return Names.Full(first, surname)
	elseif mode == "first" then
		return first
	end
	local byFirst = self.cache[first]
	if byFirst then
		local hit = byFirst[surname]
		if hit then
			return hit
		end
	else
		byFirst = {}
		self.cache[first] = byFirst
	end
	local need, total
	if mode == "initial" then
		need, total = 1, LetterCount(surname)
	else
		need, total = self:LettersNeeded(first, surname, mode == "auto" and 0 or 1)
	end
	local result
	if need <= 0 then
		result = first
	elseif need >= total then
		result = first .. " " .. surname
	else
		result = first .. " " .. Names.Prefix(surname, need) .. "."
	end
	byFirst[surname] = result
	return result
end

-- Every way this person's name may currently be written, longest first.
local function Variants(first, surname)
	local sep = Names.SEP
	local list = { first .. sep .. surname }
	if sep ~= "-" then
		list[#list + 1] = first .. "-" .. surname
	end
	if sep ~= " " then
		list[#list + 1] = first .. " " .. surname
	end
	local chars, total = Chars(surname)
	for k = total - 1, 1, -1 do
		list[#list + 1] = first .. " " .. tconcat(chars, "", 1, k) .. "."
	end
	list[#list + 1] = first
	return list
end

-- Replaces the first written form of this person's name in text with target (default: the current short form).
-- Returns newText, changed.
function Registry:Swap(text, first, surname, target)
	if type(text) ~= "string" or text == "" or type(first) ~= "string" or type(surname) ~= "string" then
		return text, false
	end
	target = target or self:Short(first, surname)
	local variants = Variants(first, surname)
	for i = 1, #variants do
		local variant = variants[i]
		local a, b = FindName(text, variant, strsub(variant, -1) ~= ".")
		if a then
			if variant == target then
				return text, false
			end
			return strsub(text, 1, a - 1) .. target .. strsub(text, b + 1), true
		end
	end
	return text, false
end

local PLAYER_LINKS = { player = true, playerCommunity = true }

-- data: "player:Frost Winterborn:lineID:chatType:target"; text: what the link shows.
function Registry:RewriteLinkText(data, text, opts)
	local linkType, rest = strmatch(data, "^([^:]*):?(.*)$")
	if not PLAYER_LINKS[linkType] then
		return text
	end
	local first, surname = Names.Split(strmatch(rest, "^([^:]*)"))
	if not surname then
		return text
	end
	if opts.learn then
		self:Learn(first, surname, opts.day)
	end
	return (self:Swap(text, first, surname))
end

-- Known "First Surname" pairs in plain text become the short form, optionally as a bracketless player link
-- so hovering still reveals (and clicking still whispers) the right person.
-- opts.skip: a full name to leave as it is (an emote's sender, which the game turns into a link afterwards).
function Registry:ReplacePlain(seg, opts)
	local sep, skip = Names.SEP, opts.skip
	local out, n, last = nil, 0, 1
	local prevStart, prevEnd, prevWord
	for s, word, e in gmatch(seg, WORD) do
		local replacement
		local between = prevWord and strsub(seg, prevEnd, s - 1)
		if between == sep or between == "-" then
			local set = self.known[prevWord]
			if set and set[word] then
				local full = prevWord .. sep .. word
				local short = self:Short(prevWord, word)
				if full ~= skip and short ~= full then
					replacement = opts.linkify and ("|Hplayer:" .. full .. "|h" .. short .. "|h") or short
					-- The game finds the emote's sender by searching the text for their name: never add it.
					if skip and strfind(replacement, skip, 1, true) then
						replacement = (not strfind(short, skip, 1, true)) and short or nil
					end
				end
			end
		end
		if replacement then
			out = out or {}
			out[n + 1] = strsub(seg, last, prevStart - 1)
			out[n + 2] = replacement
			n = n + 2
			last = e
			prevWord = nil
		else
			prevStart, prevEnd, prevWord = s, e, word
		end
	end
	if not out then
		return seg
	end
	out[n + 1] = strsub(seg, last)
	return tconcat(out)
end

-- Walks a chat line: player link texts are rewritten (their data, the real name, is never touched),
-- other links/textures/colour codes are copied as they are, plain text is handled by ReplacePlain.
-- opts: links, plain, linkify, learn, skip (see ReplacePlain), day.
function Registry:RewriteMessage(msg, opts)
	if type(msg) ~= "string" or msg == "" then
		return msg
	end
	local out, n, i, len = {}, 0, 1, #msg
	local function Plain(seg)
		n = n + 1
		out[n] = opts.plain and self:ReplacePlain(seg, opts) or seg
	end
	while i <= len do
		local p = strfind(msg, "|", i, true)
		if not p then
			Plain(strsub(msg, i))
			break
		end
		if p > i then
			Plain(strsub(msg, i, p - 1))
		end
		local code = strsub(msg, p + 1, p + 1)
		local stop
		if code == "H" then
			local h1 = strfind(msg, "|h", p + 2, true)
			local h2 = h1 and strfind(msg, "|h", h1 + 2, true)
			if h2 then
				local data = strsub(msg, p + 2, h1 - 1)
				local text = strsub(msg, h1 + 2, h2 - 1)
				if opts.links then
					text = self:RewriteLinkText(data, text, opts)
				end
				n = n + 1
				out[n] = "|H" .. data .. "|h" .. text .. "|h"
				i = h2 + 2
			else
				stop = true
			end
		elseif code == "T" or code == "A" or code == "K" then
			local close = (code == "T" and "|t") or (code == "A" and "|a") or "|k"
			local e = strfind(msg, close, p + 2, true)
			if e then
				n = n + 1
				out[n] = strsub(msg, p, e + 1)
				i = e + 2
			else
				stop = true
			end
		else
			local e = p + 1
			if code == "c" then
				if strfind(msg, "^|c%x%x%x%x%x%x%x%x", p) then
					e = p + 9
				elseif strsub(msg, p + 2, p + 2) == "n" then
					e = strfind(msg, ":", p + 3, true) or e
				end
			end
			n = n + 1
			out[n] = strsub(msg, p, e)
			i = e + 1
		end
		if stop then
			n = n + 1
			out[n] = strsub(msg, p)
			break
		end
	end
	return tconcat(out)
end

function Registry:Forget()
	for first in pairs(self.known) do
		self.known[first] = nil
	end
	self:Reindex()
end

-- Forgets people not seen for keepDays; above cap, also the least recently seen until exactly cap remain.
function Registry:Prune(keepDays, cap, today)
	today = today or Names.Today()
	local cutoff = today - (keepDays or 90)
	local known = self.known
	for first, set in pairs(known) do
		for surname, day in pairs(set) do
			if type(day) ~= "number" or day < cutoff then
				set[surname] = nil
			end
		end
		if next(set) == nil then
			known[first] = nil
		end
	end
	local count = CountKnown(known)
	if cap and count > cap then
		local all = {}
		for first, set in pairs(known) do
			for surname, day in pairs(set) do
				all[#all + 1] = { day, first, surname }
			end
		end
		tsort(all, function(x, y)
			if x[1] ~= y[1] then
				return x[1] < y[1]
			end
			if x[2] ~= y[2] then
				return ByteLess(x[2], y[2])
			end
			return ByteLess(x[3], y[3])
		end)
		for i = 1, count - cap do
			local first, surname = all[i][2], all[i][3]
			local set = known[first]
			if set then
				set[surname] = nil
				if next(set) == nil then
					known[first] = nil
				end
			end
		end
	end
	self:Reindex()
end

