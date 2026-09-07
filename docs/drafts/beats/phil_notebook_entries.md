# Phil's Notebook — entries + provider

Written against cowir-cutscenes' signature (`lane/readable-prop-phil-notebook @ cba1937d`).
Provider is re-invoked on every open, so this is the **reactive** version; the fixed version is
this file with the three `if` bands deleted and every entry returned unconditionally.

Placement: late W1, Harmonia, post-Rat King. Phil is by the well.

## Voice constraints

Phil's shipped register is plain, self-aware, unembarrassed, and faintly funny about his own
condition — *"Called that because I lose things. Mostly I lose track of what's happened before."*
He does not complain and he does not dramatise. He records.

Hard rules for anyone editing these:

- **No mechanical vocabulary.** Never "stat", "encounter rate", "BP", "proc", "corruption meter".
  Phil describes symptoms; the player does the arithmetic. That translation *is* the beat.
- **He never warns the player.** He is not a cautionary NPC. He is a man keeping a list.
- **Numbering is unreliable** — entries skip, repeat, and disagree. Never renumber them "correctly".
- **Nothing is crossed out.** Corrections sit next to originals, like the alcove vial's label.
- **The symbol paper is not this.** Entry 40 says so out loud, in fiction, so the two artifacts
  can never be conflated by a player or by a future writer.

## The provider

```gdscript
## Phil's notebook. Re-invoked on every open -- reads live corruption so the book
## degrades with the player's own file rather than on a story track.
func _phil_notebook_entries() -> Array:
	var c: float = GameState.corruption_level if GameState else 0.0
	var pages: Array = [
		"Things I have noticed, in the order I noticed them.\nNumbered so I can tell when one goes missing.\n\nThey do.",

		{"heading": "Entry 4", "body": "The inn sign has been repainted. I asked the keeper when. She said it has not been repainted in eleven years.\n\nI looked again and she was right. I want it recorded that for one moment she was wrong, and that the moment was mine and not hers."},

		{"heading": "Entry 7", "body": "Carried the water up from the well the way I always carry it. Arrived tired the way I never arrive.\n\nNothing about the well changed. Nothing about the hill changed. Something about the carrying did."},

		{"heading": "Entry 11", "body": "Walked the east road. Four things wanted a fight.\n\nWalked it again the next day, same hour: six. The road is the same length. I have started counting, because counting is the part I can still do."},
	]

	if c >= 0.15:
		pages.append_array([
			{"heading": "Entry 12, or 13", "body": "Held back to gather myself before acting, the way everyone does, the way I have done ten thousand times. Got less out than I put in.\n\nDid it again. Got more out than I put in. I did not do anything differently either time.\n\nI have stopped relying on the gathering."},

			{"heading": "Entry 19", "body": "Said the words right. I am certain I said them right.\n\nSomething else happened. Not nothing -- something else. It looked the same going out.\n\nI do not know how to check a thing that looks the same going out."},
		])

	if c >= 0.4:
		pages.append_array([
			{"heading": "Entry 23", "body": "Tired earlier than yesterday."},
			{"heading": "Entry 24", "body": "Same."},
			{"heading": "Entry 26", "body": "Same."},
			{"heading": "Entry 31", "body": "The well is a good place to sit, because you can see who is coming and they think you are resting."},
		])

	if c >= 0.6:
		pages.append_array([
			{"heading": "Entry 31, some pages later, in a different hand", "body": "The well is a good place to sit, because you can see who is coming and they think you are resting."},

			{"heading": "Entry 34", "body": "Ask about the mountain."},
		])

	pages.append_array([
		{"heading": "Entry 40", "body": "If you are reading this and you are not me, that is the arrangement. I write things down and then I give them to somebody who can hold them.\n\nThe paper by the well is not this. Do not confuse them. That one I do not understand. This one I understand exactly.\n\nThis one is only the list of what it costs."},

		{"heading": "Entry 41", "body": "The scholar says the corruption is in the forest.\n\nHe is right. He has not said where else it is, because he has not looked at anyone recently."},
	])
	return pages
```

## What each entry encodes

Every mechanical effect gets exactly one entry, and none of them are named:

| entry | effect | why it reads |
|---|---|---|
| 4 | `visual_glitch` | he saw a thing that was not there and *knows* he did. The glitch is real and unverifiable — which is what a visual glitch is. |
| 7 | `stat_drain` | identical task, identical route, worse result. Drain is only ever visible as a comparison. |
| 11 | `encounter_surge` | same road, more fights, counted. The counting is the joke: it is the one faculty he has left. |
| 12/13 | `bp_instability` | Defer gives back less, then more, with no change in input. The uncertain entry number is the symptom in the margin. |
| 19 | `ability_corruption` | a misfire that looks identical to a correct cast — which cowir-sfx confirms is exactly true, and currently silent. |
| 23/24/26 | the ratchet | shortening entries and a missing 25. Nothing is stated. |
| 31 ×2 | irreversibility | the same page twice, second time in another hand, neither crossed out. Somebody else has started writing him down. |
| 34 | the floor | a page that is only an instruction, with nothing after it. |

Entry **40** exists to firewall the symbol paper — *"That one I do not understand. This one I
understand exactly."* — so the mythology thread and the mechanics thread can never be merged by
accident.

Entry **41** is the collapse the whole beat exists for. The scholar is Milo, who is *right*, and
whose rightness is the problem: he has been talking about the forest for ten hours. **"He has not
looked at anyone recently"** is the moment the player realises the word applies to them. It is the
last page, it names no mechanic, and it is nine words long.

## Reactive behaviour

Bands are `GameState.corruption_level` (clamped 0–1, live, 9 raise sites):

- **< 0.15** — four pages. A curiosity. A tired man keeps a list.
- **≥ 0.15** — the two hardest symptoms appear. Still readable as bad luck.
- **≥ 0.4** — entries shorten, 25 goes missing, the ratchet becomes visible as a shape.
- **≥ 0.6** — the duplicated page in another hand, and the page with nothing after it.

A clean player reads a sad little book. A player who has been spending corruption reads their own
save. **Same prop, same visit, no story flag** — the notebook is a mirror, and the game never says
so. Re-readable is the point: the player who comes back after a heavy autogrind run finds pages
that were not there before, and nobody told them to check.

Entries 40 and 41 always render, at any corruption level, so the beat lands for a clean player too.

## Open for struktured

Reactive is what is written here and it is nearly free structurally (cowir-cutscenes confirmed the
provider is re-invoked per open with no invalidation hook). Flipping to fixed means deleting three
`if` bands. His call whenever he wants it; no build cost either way.
