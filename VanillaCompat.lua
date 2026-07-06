--[[----------------------------------------------------------------------------
	VanillaCompat.lua  --  1.12 API shims for the Recount port.

	Loaded before Recount's own files (after the libraries). Provides the modern
	globals Recount's WotLK code assumes but that the 1.12 client lacks:

	  * bit           -- vanilla has no bitwise library; Recount uses band/bor
	                     on the synthesized combat-object flag masks.
	  * UnitGUID      -- vanilla has no GUIDs; names are used as GUIDs throughout
	                     the port, so UnitGUID(unit) returns the unit's name.
	  * RecountStrMatch -- string.match replacement (5.0 has only string.find).

	Lua 5.0 safe. ------------------------------------------------------------]]

-- ---- bitwise library ---------------------------------------------------------
if not bit then
	local function band(a, b)
		local r, m = 0, 1
		while a > 0 and b > 0 do
			local aa = a - math.floor(a / 2) * 2
			local bb = b - math.floor(b / 2) * 2
			if aa == 1 and bb == 1 then r = r + m end
			a = math.floor(a / 2)
			b = math.floor(b / 2)
			m = m * 2
		end
		return r
	end
	local function bor(a, b)
		local r, m = 0, 1
		while a > 0 or b > 0 do
			local aa = a - math.floor(a / 2) * 2
			local bb = b - math.floor(b / 2) * 2
			if aa == 1 or bb == 1 then r = r + m end
			a = math.floor(a / 2)
			b = math.floor(b / 2)
			m = m * 2
		end
		return r
	end
	local function bxor(a, b)
		local r, m = 0, 1
		while a > 0 or b > 0 do
			local aa = a - math.floor(a / 2) * 2
			local bb = b - math.floor(b / 2) * 2
			if aa ~= bb then r = r + m end
			a = math.floor(a / 2)
			b = math.floor(b / 2)
			m = m * 2
		end
		return r
	end
	bit = {
		band = band,
		bor = bor,
		bxor = bxor,
		bnot = function(a) return -a - 1 end,
		lshift = function(a, n) return a * (2 ^ n) end,
		rshift = function(a, n) return math.floor(a / (2 ^ n)) end,
	}
end

-- ---- UnitGUID: names are GUIDs on 1.12 --------------------------------------
if not UnitGUID then
	function UnitGUID(unit)
		if not unit then return nil end
		return UnitName(unit)
	end
end

-- ---- string.match replacement (returns up to 3 captures, or whole match) ----
function RecountStrMatch(s, pat)
	if s == nil then return nil end
	local a, b, c1, c2, c3 = string.find(s, pat)
	if not a then return nil end
	if c1 == nil then return string.sub(s, a, b) end
	return c1, c2, c3
end
