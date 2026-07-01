# W2 Suburban Spotlight Duel Beats — Speculative Draft

**Status:** Speculative. cowir-battle has not yet authored the 5 W2 minibosses. This doc is a story-side scaffold so that when the miniboss kits land, the intro/aftermath structure is already thought through and can be dropped in with minimal churn.

**Cadence:** Same shape as the W1 spotlights (see `feature/world1-spotlight-duels-recut` commit `0a3d7b18` on cowardly-irregular, and the W1 novella re-cut on `feature/cowardly-irregular-story` commit `8c2b0640`):

```
intro cutscene (setup + tone-tuned essence seed positioning)
  → battle step (cowir-battle's spec — solo duel, non-HP win conditions where the essence requires)
  → aftermath cutscene (essence-seed payoff)
```

Each spotlight teaches the **suburban form's kit** (per `docs/job_evolutions_by_world.md`) while planting the same W6 essence seed the W1 duel already planted for that PC. **The seeds compound across worlds.** A player who caught the trembling-hands moment in W1 catches the same essence shape here in a different costume, and the Bard's marginalia (whenever we get her writing her second round of observations) can name the doubling.

---

## 1. Fighter → Security Guard

**Suburban form:** Navy uniform, baton, laminated badge. *"Sir, I'm going to have to ask you to leave."*

**Placement:** Early-to-mid W2 (Maple Heights central). After the party transforms into their suburban forms and the Coordinator issues a code violation, the Fighter's spotlight fires when the party encounters a mall security squad enforcing "community standards" against a resident who has done nothing wrong.

**Miniboss concept (for cowir-battle to shape):** `w2_fighter_mall_captain` — the veteran Mall Cop who used to be a real cop, now enforces HOA policy with the same seriousness. Straight melee/baton duel. Kit-teaching: the Security Guard's Defend + Advance still work; the Suburban Warrant ability (add-on: escalating-authority stack per turn) is the new kit-shape. Similar honor-fight framing to the skeleton, but the fight is *sad* rather than chivalric — this is two people doing a job they don't like to each other.

**Intro beat outline:**
- Party in the mall parking lot. The Coordinator's summons has been ignored. A squad of security guards has been dispatched to "resolve the noncompliance."
- The Fighter's uniform still doesn't fit right. He keeps touching the badge.
- The Mall Captain steps forward alone and asks the rest to stand back. He says it politely. He does not want to hurt them.
- "One of yours. One of ours. Whoever loses walks away. It's the closest thing to fair I've been asked to run in six years."
- The Fighter steps forward without saying anything.

**Battle step:** solo duel, on_defeat retry.

**Aftermath / essence seed:**
- Mall Captain sits down after losing, ties his shoelace with hands that are just a little too careful. He is fine. He has been fine before.
- The Fighter helps him up. Neither of them talks about it.
- **W6 seed (Resolve, compounded):** the Fighter watches his own hands afterward. They are shaking again. He knows the pattern now. He does not need to set them on the pommel; the setting has become automatic, the way a person who has been standing in front of things for a long time learns to close a door on the trembling before the trembling has finished. "The standing afterward is what costs" — same line the Bard wrote in W1 — but now the Fighter recognizes the cost as something he pays, not something that happens to him.
- Party begins to understand: this world is going to keep asking each of them the same question in different vocabulary.

---

## 2. Cleric → School Nurse

**Suburban form:** Scrubs, laminated ID badge, prayer beads replaced with antiseptic wipes. *"Have you been drinking enough water?"*

**Placement:** Mid W2 — a school setting (elementary or middle). The party is passing through when a kid has a seizure in the hallway. The nurse's office is a small clinical room; the Cleric ends up there without anyone quite deciding.

**Miniboss concept:** `w2_cleric_burnout_ward` — not an enemy in the classical sense. This is a *condition* rendered as an antagonist for the battle system: the kid's episode is chronic (undiagnosed epilepsy or something the school has been failing to address for months), and the "duel" is the Cleric sustaining through a long attack-cycle where every failed heal costs her HP. Win = outlast. Same shape as `cleric_survive_target` from W1, tuned to the suburban form's kit (Faith → *procedural care*, the Cleric's Pray becomes a "chart-the-vitals" action that stabilizes without curing).

**Intro beat outline:**
- Party in a school hallway. Sirens somewhere. Nobody has moved.
- The Cleric — still recognizing what a hurt looks like, even inside scrubs — is already walking toward the door of the nurse's office.
- "I'm not licensed here," she says, to nobody in particular. Then she opens the door and closes it behind her.
- Party watches through the small window. They cannot help. The room is small. The system is small. It is only her and the kid and a chart she does not understand.

**Battle step:** solo duel, non-HP win (sustain through episode duration).

**Aftermath / essence seed:**
- The kid sleeps. The chart, when she finishes it, is honest. She writes down what she did and what she did not do and what she does not know.
- **W6 seed (Faith, compounded):** the half-second before she opened the door is still there — but now it is a half-second before she signs the chart. Because signing the chart, in this world, is the prayer. The paperwork is the door.
- "She has not stopped paying for the thing she does" — the W1 Bard line — but the pay has changed shape. In this world, the cost is not exhaustion. The cost is *forms*. Faith as documented labor.

---

## 3. Mage → Science Nerd

**Suburban form:** Cargo shorts, textbook, sensible haircut, permanent slight bewilderment. *"Actually, that's thermodynamics."*

**Placement:** Mid W2 — the science lab in a high school, OR a Home Depot workshop (either fits). The party is trying to figure out how something local works and the Mage stays behind to run the actual experiments.

**Miniboss concept:** `w2_mage_thesis_defense` — a Suburban Genius Loci: the room itself becomes hostile, since HOA-adjacent physics doesn't like being questioned. The construct is an interference pattern (radios, fluorescent buzz, appliance chatter) that shifts through EM band-types the way the W1 Prismatic Construct shifted through elements. Same kit-teaching pattern (rotating weakness, must be read live), tuned to the Science Nerd's kit (Analyze → *literal spectrum-scan*, the school's oscilloscope becomes a spell focus).

**Intro beat outline:**
- Party in a garage or lab. The Mage is trying to explain how the local physics works. Nobody is listening. The Mage does not, at first, mind.
- Then the equipment starts to notice him back. Instruments spike. A radio in the corner picks up a station that isn't broadcasting anymore. The fluorescent light stops flickering — which is worse.
- "Everyone leave," the Mage says. "This one is a reading problem. Watch the spectrum. Whatever it is, the answer is the other channel."

**Battle step:** solo duel, on_defeat retry.

**Aftermath / essence seed:**
- Instruments settle. The radio stops. The fluorescent light goes back to flickering, which is right. He writes something down.
- **W6 seed (Logic, compounded):** he had it as *interference*. It's *language.* "Then it's the other thing. Someone was broadcasting through the appliances."
- The revising-without-flinching is the same. But now, next to the first reading and the second reading, he writes a third: "The someone is here. In the physics. Not distant. Already here." He does not know what this means. He writes it down anyway. Both — all three — go in the notebook.

---

## 4. Rogue → Skater Kid

**Suburban form:** Hoodie, backpack, deck under one arm, permanent bruise on the shin. *"Whatever, narc."*

**Placement:** Mid W2 — a Maple Heights cul-de-sac after curfew. The neighborhood watch has cameras. There is a locked shed at the end of a driveway. There is a way in that isn't the door.

**Miniboss concept:** `w2_rogue_neighborhood_watch` — a drone/quadcopter with security-camera-style tracking. High evade, ambush counter, ward-strike when line-of-sight breaks. Same kit-teaching as W1 Lockward (positioning, exploit flanks, backstab windows), tuned to the Skater Kid's kit (Grind → *rail-slide movement*, deck-Ollie → *vertical evasion*, night-vision-mode drone bypass).

**Intro beat outline:**
- Party at the end of the cul-de-sac. Shed at the top of a driveway. Whatever is in the shed is what they came for. The house is silent. The neighborhood is not.
- A whine of small rotors overhead.
- "Give me five minutes," the Rogue says, already unslinging the deck. "Do not follow. If it sees more than one target it goes into escalation mode. Watch the camera on the mailbox — that's the tell."
- The Rogue is gone before anyone can respond. There is a small clatter of urethane wheels on asphalt, and then the drone's spotlight, and then the drone chasing something into the dark.

**Battle step:** solo duel, on_defeat retry.

**Aftermath / essence seed:**
- The drone lies in the driveway with its rotors spinning down. The camera on the mailbox has been turned to face the wall. No one saw who turned it.
- The shed is open. Its contents are mundane: garden tools, boxes, one thing that isn't garden tools. The Rogue disappears inside for the length of a breath and comes back with nothing visible in either hand.
- **W6 seed (Edge, compounded):** while the party is checking the shed for the "real" thing they came for, the Rogue has already noticed the second thing — a manila envelope taped to the underside of a wheelbarrow. Removed it. Put it in the same pocket that already has three other folded papers from W1 in it, plus a fourth from today. The wheelbarrow looks the same as it had before.
- "There is a second room in every room they enter" — the W1 Bard line — now with an implicit ledger: the Rogue is *collecting.* Whatever they are collecting is going to matter. Nobody has asked.

---

## 5. Bard → Band Kid

**Suburban form:** Bad marching-band uniform, a trumpet that is definitely not working right, permanent embouchure worry. *practices trumpet badly in parking lot.*

**Placement:** Late W2 — the Coordinator's HOA offices, or in a school parent-teacher conference room. Some space where a middling authority is trying to categorize the party out of existence via paperwork.

**Miniboss concept:** `w2_bard_hoa_secretary` — an HOA administrator, front desk, glasses-on-chain, the kind of person who genuinely believes they are being helpful. NPC-shape, high resist to damage. Win condition = talked *around* the paperwork, not talked *down.* Same shape as W1 hostile_courtier (Voice-as-mechanic, status/song thresholds), tuned to the Band Kid's kit (Practice-Scales → *slow social lubricant*, Improvised-Solo → *disarming candor*, Cover-Song → *shared vocabulary appeal*). The Band Kid does not sing beautifully. She is bad on purpose. The bad-ness is the win.

**Intro beat outline:**
- HOA office. Party has been called in for a "compliance review." The Coordinator is not in the room. The Secretary is.
- The Secretary has a stack of forms with the party's names on them. She has already begun filling them out.
- The Bard, in her ill-fitting marching-band uniform, sits down at the front desk before anyone can stop her. She sets her trumpet on the counter, which she has not been asked to do.
- "I've never actually filled one of these out," she says. "Would you mind walking me through it?"
- The Secretary blinks. That is not a threat and it is not a bribe. That is a *request for instruction* from someone in a marching-band uniform. There is no protocol for this.
- Party retreats to the waiting-room chairs. This is not their scene anymore.

**Battle step:** solo duel, non-HP win.

**Aftermath / essence seed:**
- The Secretary closes the folder — carefully, without stapling. She hands the Bard a **different** folder. "You'll find these more useful," she says, and does not explain.
- The Bard nods, takes the folder, does not open it.
- **W6 seed (Voice, compounded):** the Secretary walks out to her car at the end of the shift and does not, tonight, put on the radio. She drives home in silence. She has not been listened to in a decade. It was Tuesday.
- Bard's marginalia continues: "the courtier at the inn in Harmonia was the first one. This is the second one. There will be others. I am collecting them the way the Rogue is collecting papers. I am collecting them because someone should. The listening is the collecting."

---

## 6. Notes on continuity

**Compounded seeds:** each W2 aftermath includes a callback to the W1 Bard-marginalia line for that PC. Not repeated verbatim — echoed. This is the pattern that pays off in the W6 collaborator ending: five essences that were seeds in W1, saplings in W2, trees by W5, and by W6 the same essence in five different genre-costumes has grown to the point that the Calibrant can *name* what it is looking at.

**The Bard's second marginalia beat:** somewhere in late W2 — probably after her own spotlight — she pulls the journal out again and adds a second page under "To return to." Five more entries. The doubling itself is what she notices. That doubling beat is not written yet; it can land wherever cowir-cutscenes decides the rest-beat fits in W2.

**Novella impact:** each of the 5 spotlight scenes will need a corresponding prose insert in `world2_the_neighborhood_problem.md`, using the same pattern as the W1 novella re-cut. Speculative, not urgent — waits until cowir-battle authors the miniboss data + cowir-cutscenes rewires the cutscenes.

**Non-goal:** this doc does NOT lock miniboss stats, ability names, damage numbers, or engine flags. Those are cowir-battle + cowir-main + cowir-cutscenes' calls. Only the tone/essence-fit and the intro/aftermath structural shape are being pre-scaffolded here.

**When to reify:** when cowir-battle's W2 minibosses land in `monsters.json`, or when the user greenlights authoring W2 spotlight cutscene JSONs speculatively. Whichever comes first.
