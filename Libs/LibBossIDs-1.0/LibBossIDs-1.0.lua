--[[ LibBossIDs-1.0 -- vanilla 1.12 stub for Recount.
     Vanilla combat text exposes no NPC IDs, so boss detection by ID is a no-op.
     Recount only reads .BossIDs[npcid]; an empty table makes IsBoss() false. ]]
local MAJOR, MINOR = "LibBossIDs-1.0", 47
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
lib.BossIDs = lib.BossIDs or {}
