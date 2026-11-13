# "Clearly you're an action gamer": the Rat-King-before-the-Elder easter egg

struktured, 2026-11-11 (relayed by cowir-main 24215 / 24216 / 24221). Story writes, cutscenes wires, ai adds one persona line.

## The scene (cowir-story): `data/cutscenes/world1_briefing_skipped.json`

- Plays on the party's FIRST return to Harmonia with the Rat King beaten and Elder Theron never spoken to.
- It REPLACES `world1_chapter1` for that save. `world1_harmonia_after_cave` ("You came back. That's the first noteworthy thing…")
  still fits afterwards and should follow it, not be replaced: nothing in it assumes the briefing happened.
- It sets the story flag `rat_king_fell_before_the_briefing` and grants the key item `unread_briefing`.
- Elder Theron is never given a pronoun, here or anywhere in the game's text. Keep it that way.

## Wiring it does NOT do (cowir-cutscenes)

The gate above chapter 1's, the completion flags the normal path would have set (talked_to_theron, chapter1/2/3 complete through
the mirror), and manual control of all five party members ("you plainly don't need the lesson").

## The optional sparring offer (main 24221), authored lines

Offered from Elder Theron's ordinary talk once the flag is set, until every trial is won. Same rewards as the normal path.

- **Prompt:** "Changed your mind? The trials are where I left them. Pick one. I will pretend this was the plan."
- **Choices** (one per unplayed spotlight duel, labelled by who fights it): "The Cleric's trial" · "The Rogue's trial" ·
  "The Mage's trial" · "The Fighter's trial" · "The Bard's trial" · "Not today."
- **On "Not today.":** "Of course not. You have a schedule. I had one too."
- **After a win:** "There. Now you know what you skipped. It was a good lesson. I stand by it."
- **When none are left:** "That was all of them. I have nothing left to teach you that you did not already do to a rat."

## The line for dynamic (LLM) Theron (cowir-ai), scoped to Theron only

"They brought you the Cave Rat King's crown before you had given your briefing. You had rehearsed that briefing, pauses and all.
You called them an action gamer and you stand by it. You are a little put out and privately impressed: tease them, never scold."
