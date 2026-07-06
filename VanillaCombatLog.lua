--[[----------------------------------------------------------------------------
	VanillaCombatLog.lua  --  1.12 combat-log translation layer for Recount

	The 3.3.5 Recount is driven by COMBAT_LOG_EVENT_UNFILTERED, a structured
	event that does not exist on the 1.12 (vanilla) client.  Vanilla exposes
	combat only as localized CHAT_MSG_* strings.

	This module reconstructs the modern event signature from those strings and
	feeds Recount's existing dispatcher unchanged:

	    Recount:CombatLogEvent(nil, timestamp, eventtype,
	        srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, <payload...>)

	Because vanilla has no GUIDs, the unit NAME is used as its GUID (names are
	effectively unique within a fight).  Unit "flags" (affiliation / reaction /
	type bitmask) are synthesized by resolving the name against the current
	group roster; unresolved names fall back to a reaction hint carried by the
	originating CHAT_MSG event.

	Pattern strings are derived at load time from the client's own GlobalStrings
	via getglobal(), so parsing is locale independent.  School names in the
	element breakdown are only mapped for enUS (cosmetic; damage totals are
	locale independent).

	Written for the Ace3v (laytya) vanilla stack.  Lua 5.0: no `...`, no `#t`,
	no string metamethods, string.gfind/gsub/find only.
------------------------------------------------------------------------------]]

local Recount = Recount
if not Recount then return end

local getglobal   = getglobal
local strfind     = string.find
local strgsub     = string.gsub
local tonumber    = tonumber
local GetTime     = GetTime
local UnitName    = UnitName
local UnitExists  = UnitExists

-- Recount combat-object flag constants (mirrors Tracker.lua / Recount.lua).
local F_MINE     = 0x00000001
local F_PARTY    = 0x00000002
local F_RAID     = 0x00000004
local F_OUTSIDER = 0x00000008
local F_FRIENDLY = 0x00000010
local F_HOSTILE  = 0x00000040
local F_CTRL_PC  = 0x00000100
local F_CTRL_NPC = 0x00000200
local F_TYPE_PC  = 0x00000400
local F_TYPE_NPC = 0x00000800
local F_TYPE_PET = 0x00001000

local FLAG_SELF      = F_MINE     + F_CTRL_PC  + F_TYPE_PC  + F_FRIENDLY
local FLAG_MYPET     = F_MINE     + F_CTRL_PC  + F_TYPE_PET + F_FRIENDLY
local FLAG_PARTY     = F_PARTY    + F_CTRL_PC  + F_TYPE_PC  + F_FRIENDLY
local FLAG_RAID      = F_RAID     + F_CTRL_PC  + F_TYPE_PC  + F_FRIENDLY
local FLAG_PARTYPET  = F_PARTY    + F_CTRL_PC  + F_TYPE_PET + F_FRIENDLY
local FLAG_FRIEND_PC = F_OUTSIDER + F_CTRL_PC  + F_TYPE_PC  + F_FRIENDLY
local FLAG_MOB       = F_OUTSIDER + F_CTRL_NPC + F_TYPE_NPC + F_HOSTILE

-- School name (enUS) -> Recount school bitmask number expected by handlers.
local SchoolToNum = {
	["Physical"] = 1, ["Holy"] = 2,  ["Fire"] = 4,   ["Nature"] = 8,
	["Frost"] = 16,   ["Shadow"] = 32, ["Arcane"] = 64,
}
local function SchoolNum(name)
	if not name then return 1 end
	return SchoolToNum[name] or 1
end

--[[--------------------------------------------------------------------------
	Roster resolution: name -> synthesized flags.
	Rebuilt on roster changes and lazily on first miss.
----------------------------------------------------------------------------]]
local NameFlags = {}
local PlayerName

local function AddUnit(unit, flag, petflag)
	if UnitExists(unit) then
		local n = UnitName(unit)
		if n then NameFlags[n] = flag end
		local pn = UnitName(unit.."pet")
		if pn then NameFlags[pn] = petflag end
	end
end

function Recount:VCL_RebuildRoster()
	NameFlags = {}
	PlayerName = UnitName("player")
	Recount.VCL_PlayerName = PlayerName
	if PlayerName then NameFlags[PlayerName] = FLAG_SELF end
	local petn = UnitName("pet")
	if petn then NameFlags[petn] = FLAG_MYPET end

	if UnitExists("raid1") then
		local i = 1
		while i <= 40 do
			AddUnit("raid"..i, FLAG_RAID, FLAG_PARTYPET)
			i = i + 1
		end
	else
		local i = 1
		while i <= 4 do
			AddUnit("party"..i, FLAG_PARTY, FLAG_PARTYPET)
			i = i + 1
		end
	end
end

-- reactionHint: FLAG_MOB or FLAG_FRIEND_PC, from the originating CHAT_MSG event.
local function FlagsFor(name, isSelf, reactionHint)
	if isSelf then return FLAG_SELF end
	if not name then return reactionHint or FLAG_MOB end
	local f = NameFlags[name]
	if f then return f end
	return reactionHint or FLAG_MOB
end

--[[--------------------------------------------------------------------------
	Pattern table.

	Each descriptor: { key = GLOBALSTRING_KEY, evt = eventtype, roles = {...},
	                   crit = bool, self = "src"|"dst"|"both"|nil, kind = ... }

	roles lists the capture order of the format string. Recognized roles:
	  "src","dst","spell","amount","school","env"
	Patterns are compiled from getglobal(key) at load.
	Descriptors with a nil global (string absent on this client) are skipped.
----------------------------------------------------------------------------]]
local D = {}
local function add(key, evt, roles, crit, selfSide)
	D[table.getn(D)+1] = {
		key=key, evt=evt, roles=roles, crit=crit, self=selfSide,
	}
end

-- ---- Melee / auto attack (SWING_DAMAGE) ---------------------------------
add("COMBATHITCRITSCHOOLSELFOTHER", "SWING_DAMAGE", {"dst","amount","school"}, true,  "src")
add("COMBATHITSCHOOLSELFOTHER",     "SWING_DAMAGE", {"dst","amount","school"}, false, "src")
add("COMBATHITCRITSELFOTHER",       "SWING_DAMAGE", {"dst","amount"},          true,  "src")
add("COMBATHITSELFOTHER",           "SWING_DAMAGE", {"dst","amount"},          false, "src")
add("COMBATHITCRITSCHOOLOTHERSELF", "SWING_DAMAGE", {"src","amount","school"}, true,  "dst")
add("COMBATHITSCHOOLOTHERSELF",     "SWING_DAMAGE", {"src","amount","school"}, false, "dst")
add("COMBATHITCRITOTHERSELF",       "SWING_DAMAGE", {"src","amount"},          true,  "dst")
add("COMBATHITOTHERSELF",           "SWING_DAMAGE", {"src","amount"},          false, "dst")
add("COMBATHITCRITSCHOOLOTHEROTHER","SWING_DAMAGE", {"src","dst","amount","school"}, true,  nil)
add("COMBATHITSCHOOLOTHEROTHER",    "SWING_DAMAGE", {"src","dst","amount","school"}, false, nil)
add("COMBATHITCRITOTHEROTHER",      "SWING_DAMAGE", {"src","dst","amount"},    true,  nil)
add("COMBATHITOTHEROTHER",          "SWING_DAMAGE", {"src","dst","amount"},    false, nil)

-- ---- Spell direct damage (SPELL_DAMAGE) ---------------------------------
add("SPELLLOGCRITSCHOOLSELFOTHER",  "SPELL_DAMAGE", {"spell","dst","amount","school"}, true,  "src")
add("SPELLLOGSCHOOLSELFOTHER",      "SPELL_DAMAGE", {"spell","dst","amount","school"}, false, "src")
add("SPELLLOGCRITSELFOTHER",        "SPELL_DAMAGE", {"spell","dst","amount"},          true,  "src")
add("SPELLLOGSELFOTHER",            "SPELL_DAMAGE", {"spell","dst","amount"},          false, "src")
add("SPELLLOGCRITSCHOOLSELFSELF",   "SPELL_DAMAGE", {"spell","amount","school"},       true,  "both")
add("SPELLLOGSCHOOLSELFSELF",       "SPELL_DAMAGE", {"spell","amount","school"},       false, "both")
add("SPELLLOGCRITSELFSELF",         "SPELL_DAMAGE", {"spell","amount"},                true,  "both")
add("SPELLLOGSELFSELF",             "SPELL_DAMAGE", {"spell","amount"},                false, "both")
add("SPELLLOGCRITSCHOOLOTHERSELF",  "SPELL_DAMAGE", {"src","spell","amount","school"}, true,  "dst")
add("SPELLLOGSCHOOLOTHERSELF",      "SPELL_DAMAGE", {"src","spell","amount","school"}, false, "dst")
add("SPELLLOGCRITOTHERSELF",        "SPELL_DAMAGE", {"src","spell","amount"},          true,  "dst")
add("SPELLLOGOTHERSELF",            "SPELL_DAMAGE", {"src","spell","amount"},          false, "dst")
add("SPELLLOGCRITSCHOOLOTHEROTHER", "SPELL_DAMAGE", {"src","spell","dst","amount","school"}, true,  nil)
add("SPELLLOGSCHOOLOTHEROTHER",     "SPELL_DAMAGE", {"src","spell","dst","amount","school"}, false, nil)
add("SPELLLOGCRITOTHEROTHER",       "SPELL_DAMAGE", {"src","spell","dst","amount"},    true,  nil)
add("SPELLLOGOTHEROTHER",           "SPELL_DAMAGE", {"src","spell","dst","amount"},    false, nil)

-- ---- Periodic / DoT damage (SPELL_PERIODIC_DAMAGE) ----------------------
add("PERIODICAURADAMAGESELFOTHER",  "SPELL_PERIODIC_DAMAGE", {"dst","amount","school","spell"},       false, "src")
add("PERIODICAURADAMAGESELFSELF",   "SPELL_PERIODIC_DAMAGE", {"amount","school","spell"},             false, "both")
add("PERIODICAURADAMAGEOTHERSELF",  "SPELL_PERIODIC_DAMAGE", {"amount","school","src","spell"},       false, "dst")
add("PERIODICAURADAMAGEOTHEROTHER", "SPELL_PERIODIC_DAMAGE", {"dst","amount","school","src","spell"}, false, nil)

-- ---- Damage shield (thorns etc.) ----------------------------------------
add("DAMAGESHIELDSELFOTHER",  "DAMAGE_SHIELD", {"dst","amount","school"}, false, "src")
add("DAMAGESHIELDOTHERSELF",  "DAMAGE_SHIELD", {"src","amount","school"}, false, "dst")
add("DAMAGESHIELDOTHEROTHER", "DAMAGE_SHIELD", {"src","dst","amount","school"}, false, nil)

-- ---- Direct heals (SPELL_HEAL) ------------------------------------------
add("HEALEDCRITSELFOTHER",  "SPELL_HEAL", {"spell","dst","amount"}, true,  "src")
add("HEALEDSELFOTHER",      "SPELL_HEAL", {"spell","dst","amount"}, false, "src")
add("HEALEDCRITSELFSELF",   "SPELL_HEAL", {"spell","amount"},       true,  "both")
add("HEALEDSELFSELF",       "SPELL_HEAL", {"spell","amount"},       false, "both")
add("HEALEDCRITOTHERSELF",  "SPELL_HEAL", {"src","spell","amount"}, true,  "dst")
add("HEALEDOTHERSELF",      "SPELL_HEAL", {"src","spell","amount"}, false, "dst")
add("HEALEDCRITOTHEROTHER", "SPELL_HEAL", {"src","spell","dst","amount"}, true,  nil)
add("HEALEDOTHEROTHER",     "SPELL_HEAL", {"src","spell","dst","amount"}, false, nil)

-- ---- Periodic heals / HoTs (SPELL_PERIODIC_HEAL) ------------------------
add("PERIODICAURAHEALSELFOTHER",  "SPELL_PERIODIC_HEAL", {"dst","amount","spell"},       false, "src")
add("PERIODICAURAHEALSELFSELF",   "SPELL_PERIODIC_HEAL", {"amount","spell"},             false, "both")
add("PERIODICAURAHEALOTHERSELF",  "SPELL_PERIODIC_HEAL", {"amount","src","spell"},       false, "dst")
add("PERIODICAURAHEALOTHEROTHER", "SPELL_PERIODIC_HEAL", {"dst","amount","src","spell"}, false, nil)

-- ---- Environmental damage (ENVIRONMENTAL_DAMAGE) ------------------------
-- env type is encoded in the key; roles carry amount (+ name for _OTHER).
local ENV = {
	DROWNING="Drowning", FALLING="Falling", FATIGUE="Fatigue",
	FIRE="Fire", LAVA="Lava", SLIME="Slime",
}
for etype, ename in pairs(ENV) do
	add("VSENVIRONMENTALDAMAGE_"..etype.."_SELF",  "ENVIRONMENTAL_DAMAGE", {"amount"},       false, "dst")
	add("VSENVIRONMENTALDAMAGE_"..etype.."_OTHER", "ENVIRONMENTAL_DAMAGE", {"dst","amount"}, false, nil)
	-- stash the friendly env name on the last two descriptors
	D[table.getn(D)-1].env = ename
	D[table.getn(D)].env   = ename
end

-- ---- Misses / avoids (SWING_MISSED, missType) ---------------------------
-- No amount; roles carry names only.
local function addMiss(key, roles, selfSide, miss)
	add(key, "SWING_MISSED", roles, false, selfSide)
	D[table.getn(D)].miss = miss
end
addMiss("MISSEDSELFOTHER",  {"dst"},       "src", "MISS")
addMiss("MISSEDOTHERSELF",  {"src"},       "dst", "MISS")
addMiss("MISSEDOTHEROTHER", {"src","dst"}, nil,   "MISS")
addMiss("VSDODGESELFOTHER",  {"dst"},       "src", "DODGE")
addMiss("VSDODGEOTHERSELF",  {"src"},       "dst", "DODGE")
addMiss("VSDODGEOTHEROTHER", {"src","dst"}, nil,   "DODGE")
addMiss("VSPARRYSELFOTHER",  {"dst"},       "src", "PARRY")
addMiss("VSPARRYOTHERSELF",  {"src"},       "dst", "PARRY")
addMiss("VSPARRYOTHEROTHER", {"src","dst"}, nil,   "PARRY")
addMiss("VSBLOCKSELFOTHER",  {"dst"},       "src", "BLOCK")
addMiss("VSBLOCKOTHERSELF",  {"src"},       "dst", "BLOCK")
addMiss("VSBLOCKOTHEROTHER", {"src","dst"}, nil,   "BLOCK")
addMiss("VSIMMUNESELFOTHER",  {"dst"},       "src", "IMMUNE")
addMiss("VSIMMUNEOTHERSELF",  {"src"},       "dst", "IMMUNE")
addMiss("VSIMMUNEOTHEROTHER", {"src","dst"}, nil,   "IMMUNE")
addMiss("VSRESISTSELFOTHER",  {"dst"},       "src", "RESIST")
addMiss("VSRESISTOTHERSELF",  {"src"},       "dst", "RESIST")
addMiss("VSRESISTOTHEROTHER", {"src","dst"}, nil,   "RESIST")
addMiss("VSEVADESELFOTHER",  {"dst"},       "src", "EVADE")
addMiss("VSEVADEOTHERSELF",  {"src"},       "dst", "EVADE")
addMiss("VSEVADEOTHEROTHER", {"src","dst"}, nil,   "EVADE")

-- ---- Deaths (UNIT_DIED) -------------------------------------------------
add("UNITDIESOTHER", "UNIT_DIED", {"dst"}, false, nil)
add("UNITDIESSELF",  "UNIT_DIED", {},      false, "dst")

--[[--------------------------------------------------------------------------
	Compile format strings -> Lua patterns.
	%s -> (.-)   (non greedy so multiple names split correctly)
	%d -> (%d+)
	The last %s in a string (a school word) is greedy-safe as trailing token.
	Positional specifiers (%1$s) are normalized to plain order.
----------------------------------------------------------------------------]]
local function compile(fmt)
	-- normalize positional args "%1$s" / "%2$d" -> "%s" / "%d"
	fmt = strgsub(fmt, "%%%d%$", "%%")
	-- escape magic chars except our specifiers
	fmt = strgsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
	-- now specifiers look like %%s / %%d after escaping of '%'? No: original % kept.
	-- Replace specifiers. Do longest first.
	fmt = strgsub(fmt, "%%s", "(.-)")
	fmt = strgsub(fmt, "%%d", "(%%d+)")
	-- anchor
	return "^"..fmt.."$"
end

local compiled = {}   -- array of {pat, desc}
local function BuildPatterns()
	compiled = {}
	local i = 1
	local n = table.getn(D)
	while i <= n do
		local desc = D[i]
		local fmt = getglobal(desc.key)
		if fmt and fmt ~= "" then
			local ok, pat = pcall(compile, fmt)
			if ok and pat then
				compiled[table.getn(compiled)+1] = { pat = pat, desc = desc }
			end
		end
		i = i + 1
	end
end

--[[--------------------------------------------------------------------------
	Dispatch a matched descriptor into Recount:CombatLogEvent.
----------------------------------------------------------------------------]]
local function Dispatch(desc, c1, c2, c3, c4, c5, reactionHint)
	-- Map ordered captures to named fields per desc.roles
	local src, dst, spell, amount, school
	local caps = { c1, c2, c3, c4, c5 }
	local r = desc.roles
	local ri = 1
	local nr = table.getn(r)
	while ri <= nr do
		local role = r[ri]
		local v = caps[ri]
		if role == "src" then src = v
		elseif role == "dst" then dst = v
		elseif role == "spell" then spell = v
		elseif role == "amount" then amount = tonumber(v)
		elseif role == "school" then school = v
		end
		ri = ri + 1
	end

	-- Fill self-implied names
	local selfName = PlayerName or UnitName("player")
	local srcSelf, dstSelf = false, false
	if desc.self == "src" then src = selfName; srcSelf = true
	elseif desc.self == "dst" then dst = selfName; dstSelf = true
	elseif desc.self == "both" then src = selfName; dst = selfName; srcSelf = true; dstSelf = true
	end

	local srcFlags = FlagsFor(src, srcSelf, reactionHint)
	local dstFlags = FlagsFor(dst, dstSelf, reactionHint)
	local ts = GetTime()
	local schoolNum = SchoolNum(school)

	local evt = desc.evt
	if evt == "SWING_DAMAGE" then
		if desc.miss then
			-- SwingMissed(ts,evt,srcGUID,srcName,srcFlags,dstGUID,dstName,dstFlags, missType, missAmount)
			Recount:CombatLogEvent(nil, ts, "SWING_MISSED", src, src, srcFlags, dst, dst, dstFlags,
				desc.miss, nil)
		else
			-- SwingDamage(...,amount,overkill,school,resisted,blocked,absorbed,critical,glancing,crushing)
			Recount:CombatLogEvent(nil, ts, "SWING_DAMAGE", src, src, srcFlags, dst, dst, dstFlags,
				amount or 0, 0, schoolNum, 0, nil, nil, desc.crit, nil, nil)
		end
	elseif evt == "SPELL_DAMAGE" or evt == "SPELL_PERIODIC_DAMAGE" or evt == "DAMAGE_SHIELD" then
		-- SpellDamage(...,spellId,spellName,spellSchool,amount,overkill,school,resisted,blocked,absorbed,critical,glancing,crushing)
		Recount:CombatLogEvent(nil, ts, evt, src, src, srcFlags, dst, dst, dstFlags,
			0, spell or "Unknown", schoolNum, amount or 0, 0, schoolNum, 0, nil, nil, desc.crit, nil, nil)
	elseif evt == "SPELL_HEAL" or evt == "SPELL_PERIODIC_HEAL" then
		-- SpellHeal(...,spellId,spellName,spellSchool,amount,overheal,absorbed,critical)
		Recount:CombatLogEvent(nil, ts, evt, src, src, srcFlags, dst, dst, dstFlags,
			0, spell or "Unknown", schoolNum, amount or 0, 0, nil, desc.crit)
	elseif evt == "ENVIRONMENTAL_DAMAGE" then
		-- EnvironmentalDamage(...,environmentalType,amount,overkill,school,resisted,blocked,absorbed,...)
		Recount:CombatLogEvent(nil, ts, "ENVIRONMENTAL_DAMAGE", nil, nil, 0, dst, dst, dstFlags,
			desc.env or "Falling", amount or 0, 0, schoolNum, 0, nil, nil, nil, nil, nil)
	elseif evt == "UNIT_DIED" then
		Recount:CombatLogEvent(nil, ts, "UNIT_DIED", nil, nil, 0, dst, dst, dstFlags)
	end
end

--[[--------------------------------------------------------------------------
	Event frame.
	reactionHints keyed by CHAT_MSG event give the likely reaction/type of an
	otherwise-unresolved named unit in that message.
----------------------------------------------------------------------------]]
local HOSTILE_EVENTS = {
	["CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"]=true, ["CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES"]=true,
	["CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"]=true, ["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]=true,
	["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"]=true,
	["CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"]=true, ["CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"]=true,
	["CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS"]=true, ["CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES"]=true,
	["CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS"]=true, ["CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_MISSES"]=true,
	["CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"]=true, ["CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE"]=true,
	["CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE"]=true,
	["CHAT_MSG_SPELL_PERIODIC_CREATURE_VS_SELF_DAMAGE"]=true,
	["CHAT_MSG_SPELL_PERIODIC_CREATURE_VS_PARTY_DAMAGE"]=true,
	["CHAT_MSG_SPELL_PERIODIC_CREATURE_VS_CREATURE_DAMAGE"]=true,
	["CHAT_MSG_COMBAT_HOSTILE_DEATH"]=true,
}

local COMBAT_EVENTS = {
	"CHAT_MSG_COMBAT_SELF_HITS","CHAT_MSG_COMBAT_SELF_MISSES",
	"CHAT_MSG_COMBAT_PET_HITS","CHAT_MSG_COMBAT_PET_MISSES",
	"CHAT_MSG_COMBAT_PARTY_HITS","CHAT_MSG_COMBAT_PARTY_MISSES",
	"CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS","CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES",
	"CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS","CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
	"CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS","CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
	"CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS","CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES",
	"CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS","CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_MISSES",
	"CHAT_MSG_SPELL_SELF_DAMAGE","CHAT_MSG_SPELL_SELF_BUFF",
	"CHAT_MSG_SPELL_PET_DAMAGE","CHAT_MSG_SPELL_PET_BUFF",
	"CHAT_MSG_SPELL_PARTY_DAMAGE","CHAT_MSG_SPELL_PARTY_BUFF",
	"CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE","CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
	"CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE","CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
	"CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE","CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF",
	"CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE","CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE","CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE","CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_VS_SELF_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_VS_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_VS_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF","CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",
	"CHAT_MSG_COMBAT_FRIENDLY_DEATH","CHAT_MSG_COMBAT_HOSTILE_DEATH",
}

local function OnMessage(msg, hint)
	local n = table.getn(compiled)
	local i = 1
	while i <= n do
		local entry = compiled[i]
		local a, b, c1, c2, c3, c4, c5 = strfind(msg, entry.pat)
		if a then
			Dispatch(entry.desc, c1, c2, c3, c4, c5, hint)
			return
		end
		i = i + 1
	end
end

local frame = CreateFrame("Frame", "RecountVCLFrame")
frame:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE"
	   or event == "PARTY_MEMBERS_CHANGED" or event == "UNIT_PET" then
		Recount:VCL_RebuildRoster()
		return
	end
	-- combat message
	local hint = HOSTILE_EVENTS[event] and FLAG_MOB or FLAG_FRIEND_PC
	OnMessage(arg1, hint)
end)

function Recount:VCL_Enable()
	BuildPatterns()
	Recount:VCL_RebuildRoster()
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("RAID_ROSTER_UPDATE")
	frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
	frame:RegisterEvent("UNIT_PET")
	local i = 1
	local n = table.getn(COMBAT_EVENTS)
	while i <= n do
		frame:RegisterEvent(COMBAT_EVENTS[i])
		i = i + 1
	end
end

-- Enabled from Recount:OnEnable (see Recount.lua port); safe to call now too.
Recount:VCL_Enable()
