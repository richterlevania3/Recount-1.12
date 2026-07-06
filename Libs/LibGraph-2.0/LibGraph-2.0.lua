--[[ LibGraph-2.0 -- vanilla 1.12 stub for Recount.
     The real LibGraph draws line/bar graphs via runtime texture tessellation
     using APIs that differ on 1.12. This stub satisfies the constructor API so
     the graph windows LOAD without error; the plotted lines are not drawn yet.
     Porting the real renderer is tracked in PORTING.md (graph output).
     Lua 5.0 safe. ]]

local MAJOR, MINOR = "LibGraph-2.0", 45
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Any method called on a returned graph frame is a harmless no-op that
-- returns the frame, so call chains do not error.
local function noop() end

local function MakeGraph(name, parent)
	local f = CreateFrame("Frame", name, parent)
	-- attach permissive no-op graph methods
	local methods = {
		"AddDataSeries", "AddTimeData", "ResetData", "SetXAxis", "SetYAxis",
		"SetGridSpacing", "SetGridColor", "SetAxisDrawing", "SetAutoScale",
		"SetBarColors", "AddBar", "RefreshGraph", "SetMode", "LockXMin",
		"SetXAxisMode", "SetYMax", "SetYMin", "SetFilterRadius", "DrawLineSegs",
		"DrawLine", "SetName", "SetGraphType", "SetLineTexture", "SetColorTable",
	}
	local i = 1
	local n = table.getn(methods)
	while i <= n do
		f[methods[i]] = noop
		i = i + 1
	end
	return f
end

function lib:CreateGraphLine(name, parent) return MakeGraph(name, parent) end
function lib:CreateGraphRealtimeLine(name, parent) return MakeGraph(name, parent) end
function lib:CreateGraphBar(name, parent) return MakeGraph(name, parent) end
function lib:CreateGraphScatterPlot(name, parent) return MakeGraph(name, parent) end
function lib:CreateGraphPieChart(name, parent) return MakeGraph(name, parent) end
