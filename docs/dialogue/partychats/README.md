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

## Files

- `w3_chat_teatime_brasston.json` — Brasston's 4:07pm scheduled teatime (sample)
- `w4_chat_manifest_denial.json` — Rivet Row manifest bureaucracy (sample)
- `w5_chat_root_access.json` — Node Prime privilege philosophy (sample)
- `w6_chat_the_remainder.json` — Abstract's rounding error (sample)

## Format reminder

Party chats are LIGHT banter, not story beats. Keep them:
- Short (2-4 dialogue blocks, optional narration opener/closer)
- Character-driven (reveals who they are, not what they do)
- Low-stakes (no plot advances; no new threats)
- Letterboxed (consistent with other cutscenes)
- `set_flag: party_chat_viewed_<id>` at end so they don't re-appear in menu
