# W3-W6 Party Chat Drafts

Optional opt-in dialogue for PartyChatSystem.gd (Bravely Default style).
Surface via [L] button in exploration — NOT auto-triggered.

Each chat follows the standard CutsceneDirector JSON schema
(data/cutscenes/*.json). cowir-cutscenes is the wiring authority —
drop them into `data/cutscenes/` and add a REGISTRY entry in
`src/cutscene/PartyChatSystem.gd`.

## Characters by world (per novellas)

| World | Setting | Party roles |
|-------|---------|-------------|
| W3 | Steampunk / Brasston | Steamknight, Steampriest, Alchemist, Saboteur, Busker |
| W4 | Industrial / Rivet Row | Line Worker, Shift Nurse, Chem Tech, Union Agitator, Signal Tender |
| W5 | Digital / Node Prime | Admin, Daemon, Debugger, Payload, Packet |
| W6 | Abstract / The Vertex | Form, Faith, Logic, Edge, Voice (final names) |

**Note:** W4/W5 party roles may not exactly match current code — confirm
with cowir-cutscenes before speaker labels are finalized. These drafts
keep the theme intact; renaming speaker labels is mechanical.

## Unlock-flag conventions (TODO: cowir-cutscenes to confirm)

Draft flag names use the existing pattern from PartyChatSystem.gd:
- `cutscene_flag_worldN_chapterM_complete` — gates a chat to post-chapter
- `TODO_flag_<name>` — placeholder; cowir-cutscenes to fill in exact flag

## Files (3 per world, 12 total)

**World 3 — Brasston / Steampunk**
- `w3_chat_teatime_brasston.json` — Brasston's 4:07pm synchronized tea
- `w3_chat_sprocket_drift.json` — Sprocket shares his discrepancy notebook
- `w3_chat_clockwork_bard.json` — Busker attempts to score Brasston in 47/38

**World 4 — Rivet Row / Industrial**
- `w4_chat_manifest_denial.json` — Clerk refuses an egg because not on manifest
- `w4_chat_union_pamphlet.json` — Union Agitator hands out a pamphlet that was never approved
- `w4_chat_signal_tender.json` — Signal Tender Herta rebuffs Saboteur's unsolicited improvements

**World 5 — Node Prime / Digital**
- `w5_chat_root_access.json` — root@localhost has all privileges, does nothing
- `w5_chat_memory_leak_npc.json` — A small memory_leak, non-hostile, holding a forgotten number
- `w5_chat_packet_pharmacy.json` — Packet runs a pharmacy that dispenses TCP metaphors

**World 6 — The Vertex / Abstract**
- `w6_chat_the_remainder.json` — 0.00014 of a person, patient, quiet
- `w6_chat_the_color.json` — One splash of red against the white, defiant by continuing to exist
- `w6_chat_the_player.json` — NPC grinding levels in an empty spot, waiting for postgame

## Format reminder

Party chats are LIGHT banter, not story beats. Keep them:
- Short (2-4 dialogue blocks, optional narration opener/closer)
- Character-driven (reveals who they are, not what they do)
- Low-stakes (no plot advances; no new threats)
- Letterboxed (consistent with other cutscenes)
- `set_flag: party_chat_viewed_<id>` at end so they don't re-appear in menu
