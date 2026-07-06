# Recount — Vanilla 1.12 port (work in progress)

A backport of **Recount v4.0.1** (Cryect / Elsia, the WotLK damage & healing
meter) to the vanilla **1.12 client**.

> **Status: foundation complete, core conversion in progress — does not load yet.**
> See [PORTING.md](PORTING.md) for exactly what remains.

Recount was never a vanilla addon: on 3.3.5 it is driven entirely by
`COMBAT_LOG_EVENT_UNFILTERED`, a structured combat log that **does not exist on
1.12**. No working 1.12 Recount exists anywhere (verified July 2026), so this is
a genuine from-scratch port, not a repackage.

## What the port does

1. **Combat-log translation layer** ([`VanillaCombatLog.lua`](VanillaCombatLog.lua)) —
   the novel piece. Vanilla exposes combat only as localized `CHAT_MSG_*`
   strings. This module compiles Lua patterns from the client's own
   `GlobalStrings` (locale-independent), parses every combat message, and
   reconstructs the modern event signature that Recount's `Tracker` expects:

   ```
   Recount:CombatLogEvent(nil, timestamp, eventtype,
       srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, <payload…>)
   ```

   Names stand in for GUIDs (unique within a fight); unit flags (affiliation /
   reaction / type bitmask) are synthesized from the group roster plus a
   reaction hint carried by each `CHAT_MSG` event. This lets Recount's ~76 KB
   `Tracker.lua` dispatcher run **unchanged** — the port swaps the data source,
   not the accounting.

   Covered today: melee/auto, spell direct & periodic (DoT) damage, damage
   shields, direct & periodic heals, environmental damage, misses/dodges/
   parries/blocks/immunes/resists/evades, and unit deaths. Deferred: drains,
   leeches, absorb-as-event, extra attacks, interrupts, dispels, cast tracking
   (see PORTING.md).

2. **Ace3v library stack** — every Ace3 library is replaced with the vanilla
   [laytya/Ace3v](https://github.com/laytya/Ace3v) build (Lua 5.0 calling
   convention). `LibBossIDs`, `LibSharedMedia`, and `LibGraph` are replaced with
   compact vanilla stubs under `Libs/` (graph rendering is stubbed, not yet
   ported).

## Install

Copy the `Recount` folder into `Interface/AddOns/`. **Not yet functional** — the
core Lua 5.1→5.0 conversion (PORTING.md) must land first.

## Credits

Original Recount by **Cryect**, 2.4+ maintenance by **Elsia**. Vanilla Ace3
stack by **laytya**. Combat-parsing approach follows the well-trodden
SW_Stats / DPSMate `getglobal`-pattern technique. This port is an independent
community backport.
