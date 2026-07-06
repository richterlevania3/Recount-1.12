--[[ LibSharedMedia-3.0 -- compact vanilla 1.12 implementation for Recount.
     Provides the subset of the LSM API that Recount uses: MediaType constants,
     Register, Fetch, List, HashTable, IsValid, and a no-op callback registrar.
     Written for Lua 5.0 (no string metamethods, no #). ]]

local MAJOR, MINOR = "LibSharedMedia-3.0", 8
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MediaTypes = lib.MediaTypes or {
	BACKGROUND = "background",
	BORDER     = "border",
	FONT       = "font",
	STATUSBAR  = "statusbar",
	SOUND      = "sound",
}

lib.MediaTable = lib.MediaTable or {}
lib.DefaultMedia = lib.DefaultMedia or {}

local function ensure(mediatype)
	if not lib.MediaTable[mediatype] then lib.MediaTable[mediatype] = {} end
	return lib.MediaTable[mediatype]
end

-- Vanilla-safe defaults
do
	local fonts = ensure("font")
	fonts["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF"
	fonts["Arial Narrow"]     = "Fonts\\ARIALN.TTF"
	fonts["Skurri"]           = "Fonts\\SKURRI.TTF"
	fonts["Morpheus"]         = "Fonts\\MORPHEUS.TTF"
	lib.DefaultMedia.font = "Friz Quadrata TT"

	local bars = ensure("statusbar")
	bars["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar"
	lib.DefaultMedia.statusbar = "Blizzard"

	local sounds = ensure("sound")
	sounds["None"] = "Interface\\Quiet.ogg"
	lib.DefaultMedia.sound = "None"

	local bg = ensure("background")
	bg["None"] = "Interface\\Tooltips\\UI-Tooltip-Background"
	lib.DefaultMedia.background = "None"

	local border = ensure("border")
	border["None"] = "Interface\\Tooltips\\UI-Tooltip-Border"
	lib.DefaultMedia.border = "None"
end

function lib:Register(mediatype, key, data)
	if type(mediatype) ~= "string" or type(key) ~= "string" then return false end
	mediatype = string.lower(mediatype)
	ensure(mediatype)[key] = data
	return true
end

function lib:Fetch(mediatype, key, noDefault)
	mediatype = string.lower(mediatype)
	local t = lib.MediaTable[mediatype]
	local v = t and t[key]
	if v then return v end
	if noDefault then return nil end
	local d = lib.DefaultMedia[mediatype]
	return t and d and t[d] or nil
end

function lib:IsValid(mediatype, key)
	mediatype = string.lower(mediatype)
	local t = lib.MediaTable[mediatype]
	if not t then return false end
	if key == nil then return true end
	return t[key] ~= nil
end

function lib:HashTable(mediatype)
	return ensure(string.lower(mediatype))
end

function lib:List(mediatype)
	mediatype = string.lower(mediatype)
	local t = lib.MediaTable[mediatype]
	local list = {}
	if t then
		local n = 0
		for k in pairs(t) do n = n + 1; list[n] = k end
	end
	table.sort(list)
	return list
end

function lib:GetDefault(mediatype)
	return lib.DefaultMedia[string.lower(mediatype)]
end

function lib:SetDefault(mediatype, key)
	mediatype = string.lower(mediatype)
	if lib.MediaTable[mediatype] and lib.MediaTable[mediatype][key] then
		lib.DefaultMedia[mediatype] = key
		return true
	end
	return false
end

-- Callback registration is a no-op on this stub (no dynamic media changes).
function lib.RegisterCallback() end
function lib.UnregisterCallback() end
function lib.UnregisterAllCallbacks() end
