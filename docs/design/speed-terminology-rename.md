# "Showcase / Spotlight Speed" — Rename Candidates

*cowir-story, 2026-07-25. For struktured. Pick-one, not a discussion doc.*

## The ask

Struktured: the "showcase/spotlight speed" terminology collides with Spotlight Duels
and he wants it renamed. This doc turns that into four options with their costs.

## What I found first — the collision is THREE-way, not two

Everyone has been describing this as two terms colliding. It's three:

| Term | Means | Where | Load-bearing? |
|---|---|---|---|
| **Spotlight Duel** | A 1v1 miniboss that unlocks a PC's manual control | 13 identifiers, quests, cutscenes, tutorials | **Yes** — in-fiction, shipped, player-known |
| **Ability Showcase** | Presentation mode: dim → step out → telegraph → impact → settle, queue serialized so one actor holds the stage | 48 refs, all `BattleScene.gd` | Internal only |
| **"Showcase NPC"** | The three Wave-D LLM-persona demo NPCs (Theron / Milo / Boris) | 16 refs across `OverworldNPC`/`HarmoniaVillage`/`DynamicConversation` + the **filename** `npc_showcase_personas.json` | Internal only |

The third meaning is the one nobody flagged. It is unrelated to battle — it means
"NPC we built to show off the LLM dialogue feature." It survives any rename of the
battle term and will keep muddying greps for `showcase` regardless of what we pick.

## Second finding — this is almost entirely an INTERNAL problem

The battle-speed setting has **no player-facing "showcase" label at all.** Verified by
reading the settings construction rather than grepping for the word
(`SettingsMenu.gd:340`): the row is titled **"Battle Speed Default"**, described as
**"Default battle animation speed"**, and its values are bare multipliers
(`1x / 2x / 4x / 8x / 16x`). The player never encounters "showcase" or "spotlight"
anywhere on this setting.

There is exactly **one** player-facing string containing the collision, and it
contains both halves in a single sentence — `TutorialHints.gd:87`:

> "...until you unlock them by winning their **Spotlight Duel** — a 1v1 miniboss that
> **showcases** what THAT character does best. Look for their **spotlight** beat..."

So: player-facing cost of any rename is ~1 string. The expensive part is identifiers,
and the identifiers are three different concepts sharing one word.

## Ground rule for candidates

**"Spotlight" stays put.** It's in-fiction, shipped, and player-known. The *speed/
presentation* concept is the one that moves. Candidates avoid the theater word-family
entirely (stage, limelight, marquee, spotlight) — reusing that root re-collides the
first time someone writes "spotlight showcase speed."

Also required: the name must still fit after the mode gets showier, since struktured
has already said it "needs more flash."

## The four options

| # | Name | One-line tradeoff |
|---|---|---|
| 1 | **Cinematic** | Safest and already his own informal word for it — but generic; every game ships a "cinematic mode," so it names the tempo without saying anything about *this* game. |
| 2 | **Full Render** | Mechanically honest — it's the exact opposite pole from Ludicrous ("pure math, no rendering"), so the speed ladder becomes one coherent axis — but reads technical rather than in-fiction. |
| 3 | **Ceremony** | Best tonal fit for W1's administrative satire (the Lockward has PROTOCOL, guards "act accordingly") and inherently ornate so it *grows* with more flash — but sits oddly in the W5/W6 digital worlds. |
| 4 | **No player term; rename code only** | Cheapest by far and arguably correct given the player never sees the word — fixes team vocabulary, ships zero player-facing change — but leaves the mode nameless in conversation, which is how it got confusing in the first place. |

## Recommendation

**Option 2 (Full Render)**, with option 4 as the cheap fallback.

Reason: it's the only candidate that makes the speed ladder *mean* something. The
game already has `HeadlessBattleResolver` — Ludicrous Speed resolves battles as pure
math with no rendering. Naming the opposite pole "Full Render" makes the whole
setting one honest axis (how much of this battle do you actually want drawn?), which
is exactly the game's thesis about automation. It also grows correctly: more flash
is literally more render.

If that reads too technical for a player-facing label, option 4 costs nothing and
loses nothing, because the label doesn't currently exist.

## Separate decision, cheap either way

The **"showcase NPC"** meaning (Theron/Milo/Boris) wants its own word regardless of
what wins above — `demo NPC`, `persona NPC`, or `dynamic NPC` all work, with
`persona NPC` matching the existing `npc_showcase_personas.json` content best. That
rename touches a data filename, so it is a slightly bigger diff than its size
suggests. Worth doing at the same time so `grep showcase` becomes meaningful again;
not worth doing alone.

## Cost summary if he picks a rename

- **Player-facing:** 1 string (`TutorialHints.gd:87`).
- **Battle identifiers:** 48 refs, one file (`BattleScene.gd`) — mechanical, cowir-battle's lane.
- **NPC identifiers:** 16 refs + 1 data filename — separate decision above.

No behavior changes in any option. Nothing here touches balance.
