# Porting status & remaining work

## Done

- [x] Confirmed no vanilla Recount exists anywhere (would-be duplicate check).
- [x] Full vanilla **Ace3v** library stack swapped in (`Libs/`, from laytya/Ace3v).
- [x] `LibBossIDs`, `LibSharedMedia`, `LibGraph` replaced with vanilla stubs.
- [x] `Recount.toc` rewritten: `## Interface: 11200`, libs loaded from the TOC
      (not a root XML — an Ace3v ordering lesson from the Bartender4 port),
      `VanillaCombatLog.lua` inserted after `Tracker.lua`.
- [x] **Combat-log translation layer** (`VanillaCombatLog.lua`) — parses vanilla
      `CHAT_MSG_*` combat text into Recount's `CombatLogEvent` signature.
      Lua-5.0 clean, syntax-validated.

## Done — Lua 5.1 → 5.0 conversion pass (static)

- [x] `#t` length operator → `table.getn(t)` (107 sites across 13 files).
- [x] Varargs rewritten to Lua 5.0 `arg`/`unpack(arg)`
      (Tracker `CombatLogEvent`, WindowOrder, LazySync, Recount_Modes).
- [x] `string.match` → `RecountStrMatch` shim; `string_match` locals repointed.
- [x] String-literal colon methods (`("%.1f"):format` etc.) → `string.format`,
      `string.reverse`/`string.gsub` (GUI_Main).
- [x] Dead `COMBAT_LOG_EVENT_UNFILTERED` registration removed; Recount's setup
      now calls `Recount:VCL_Enable()`.
- [x] `VanillaCompat.lua` shims: `bit` library, `UnitGUID` (→ UnitName),
      `RecountStrMatch`. Loaded before Recount's files.
- [x] Every `.lua` passes `luac -p`; no `#`/`select`/`string.match`/string-colon
      idioms remain in code.

## Remaining — in-game shakeout (cannot be validated statically)

- **First load test** on a 1.12 client — capture any Lua error traceback.
- `table.getn` vs `n`-desync: the append idiom now uses `table.getn`; if any
  table mixes `table.insert` and `[getn+1]=` writes, counts can drift. Watch
  detail-window row counts.
- **AceGUI/AceConfig options dialog** (`/recount` → config): exercise every
  widget; Ace3v quirks surface here.
- **Graphs** (`GUI_Graph`/`GUI_DeathGraph`/`GUI_Realtime`): `LibGraph` is a
  no-op stub — windows should open but plot nothing until the renderer is ported.
- **LazySync** (AceComm/AceSerializer cross-player sync): loads; recommend
  leaving disabled for first verification.

## Original inventory (for reference)

| File | `#t` len-op | varargs `...` | `s:method()` | `string.match` |
|------|:-:|:-:|:-:|:-:|
| Recount.lua      | 23 | 0 | 11 | 4 |
| Tracker.lua      | 8  | 4 | 4  | 2 |
| GUI_Detail.lua   | 38 | 0 | 0  | 0 |
| GUI_Graph.lua    | 16 | 1 | 0  | 0 |
| GUI_Main.lua     | 3  | 1 | 7  | 1 |
| LazySync.lua     | 9  | 3 | 2  | 5 |
| roster.lua       | 0  | 0 | 6  | 3 |
| Recount_Modes.lua| 2  | 2 | 0  | 0 |
| WindowOrder.lua  | 2  | 3 | 0  | 0 (+2 `select`) |
| Fights / Fonts / colors / GUI_Config / GUI_Realtime / deletion | ~1 each | 0–1 | 0 | 0–1 |

Conversion rules:
- `#t` → `table.getn(t)`
- `t[#t+1] = v` → `table.insert(t, v)` / explicit counter
- `local a,b = ...` and `select('#'/'n', ...)` → 5.0 `arg` table (`arg.n`, `arg[i]`)
  or fixed positional params. Ace3v's `AceCore.countargs` / explicit argc helpers
  are the intended pattern (see how Bartender4-1.12 does it).
- `("x"):find(...)` → `string.find("x", ...)`; likewise gsub/format/sub.
- `string.match` → `string.find` with captures; `string.gmatch` → `string.gfind`.

## Remaining — vanilla API gaps to audit at runtime

- **Remove the dead `COMBAT_LOG_EVENT_UNFILTERED` registration** in `Recount.lua`
  (~line 2021). `RegisterEvent` on an unknown event errors on 1.12; the new
  parser drives `CombatLogEvent` instead.
- `GetSpellInfo`, `UnitGUID`, `GetTime` precision, `CombatLog_Object_IsA`,
  `bit` library availability — audit; provide shims where Tracker/roster expect
  modern APIs. (Flags are already synthesized by the parser, so most GUID/flag
  paths are fed valid data.)
- **LazySync** (cross-player sync via AceComm/AceSerializer): the libs are
  present, but sync is non-essential — recommend disabling for the first
  working build.
- **Graphs** (`GUI_Graph`, `GUI_DeathGraph`, `GUI_Realtime`): `LibGraph` is a
  no-op stub, so windows load but plot nothing. Porting the real texture
  renderer to 1.12 is a follow-up milestone.
- **AceGUI-on-vanilla** config dialog (`/recount` options): exercise every
  widget Recount's `GUI_Config` builds; Ace3v widget quirks surface here.

## Suggested milestone order

1. Land the mechanical Lua 5.0 conversion so the addon **loads** clean.
2. Verify core meter in-game: DPS, HPS, damage taken, deaths (bars + detail).
3. Options dialog and window management.
4. Graph rendering.
5. Long-tail events (drains/leeches/absorbs/interrupts/dispels) in the parser.

In-game testing on an actual 1.12 client (Wallcraft / OctoWoW) is required at
each step — it cannot be validated statically.
