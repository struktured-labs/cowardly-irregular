extends GutTest

## The banner event names the Chancellor; one turn later Theron calls her "he".
##
## `_pronoun_note` fires on a figure "named in the conversation so far", and every
## builder picked its own idea of what that meant:
##
##     build_npc_opening       its recent_events
##     build_npc_reply         last_npc_line + player_line ONLY
##     build_combined_reply    last_npc_line + player_line ONLY
##     build_player_choices    nothing at all — no note on this path
##
## So a reply whose EVENTS, MEMORY or QUEST block names her got no note, while the
## opening one turn earlier did. Exactly the case the opening arm was added for,
## moved forward a single exchange — and the blocks a reply carries are the same
## ones the opening carries.
##
## MEASURED against live llama3 on the shipped prompts, 8 samples per call site.
## Scenario: the events block says "Chancellor Mordaine's banners went up over
## Castle Harmonia"; the NPC's last line and the player's line never name her.
##
##     path            shipped                          after
##     combined reply  5 of 8 he/him, 0 she/her          0 of 8, correct 7
##     npc reply       1 of 8 he/him, 0 she/her          0 of 8, correct 6
##     ─────────────────────────────────────────────────────────────────
##     of the SHIPPED samples that used a gendered pronoun at all: 6 of 6 WRONG
##     of the FIXED   samples that used one:                       13 of 13 right
##
## "You mean Mordaine, no doubt. HIS ambition knows no bounds." — and the combined
## path puts it in the menu too: "Can we reason with HIM?" is a player choice the
## model wrote.
##
## ⚠️ THE MEMORY BLOCK SHOWED NO HARM, 0 of 8 either way. Those replies acknowledge
## the past visit without pronominalising her (4 of 8 named her with no pronoun at
## all). So the events block is where this was observed; memory and quest are the
## same construction and are guarded as such, not as measured defects.
##
## The repair is the scan input, not more prompt text: the note is now derived from
## the assembled body, so no block can name a figure without it firing. Same way
## _context_blocks closed the block-drift class — by construction rather than by a
## guard noticing the next missing one.

const DP := preload("res://src/llm/DialoguePrompts.gd")

const PERSONA := "Elder Theron, keeper of Harmonia's records."
const HER := "Chancellor Mordaine"
const NOTE := "Chancellor Mordaine uses she/her"

const NEUTRAL_EVENTS: Array = [{"type": "battle", "summary": "The party defeated the Cave Rat King."}]
const NEUTRAL_QUEST: Array = ["Milo is still counting his sample sizes"]
const NEUTRAL_MEMORY: Array = ["the player asked about the road north last time"]
const NEUTRAL_LAST := "You came back."
const NEUTRAL_SAID := "What happens to the town now?"


## One prompt per slot she can be named in, with every OTHER slot kept neutral —
## so a passing arm proves that slot alone triggers the note.
func _reply_naming_her_in(slot: String) -> String:
	var npc: String = "Elder Theron"
	var persona: String = PERSONA
	var events: Array = NEUTRAL_EVENTS
	var quest: Array = NEUTRAL_QUEST
	var memory: Array = NEUTRAL_MEMORY
	var last: String = NEUTRAL_LAST
	var said: String = NEUTRAL_SAID
	match slot:
		"events":
			events = [{"type": "story", "summary": "%s's banners went up over the castle." % HER}]
		"memory":
			memory = ["the player asked about %s last time" % HER]
		"quest":
			quest = ["%s has summoned the council again" % HER]
		"npc_name":
			npc = HER
		"persona":
			persona = "A clerk appointed by %s." % HER
		"last_npc_line":
			last = "%s will hear of this." % HER
		"player_line":
			said = "What does %s want?" % HER
		_:
			fail_test("unknown slot '%s'" % slot)
	return DP.build_npc_reply(npc, persona, "Harmonia", events, last, said,
		quest, "evening", {}, memory)


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_reply_whose_events_name_her_carries_the_note() -> void:
	## THE ARM, and the one measured: 6 of 6 gendered shipped samples said "he".
	var p: String = _reply_naming_her_in("events")
	assert_true(p.find(HER) != -1,
		"CONTROL: the fixture must actually name her in the prompt")
	assert_true(p.find(NOTE) != -1,
		"an events block that names her must carry her pronoun — the opening's arm, one turn later")


func test_every_block_a_reply_carries_triggers_the_note_on_its_own() -> void:
	## The construction claim, stated as behaviour: whichever slot names her, the
	## note fires. A builder that scans a hand-picked subset fails here for the
	## slots it forgot, which is how all four came to disagree.
	var missing: Array[String] = []
	for slot in ["events", "memory", "quest", "npc_name", "persona",
			"last_npc_line", "player_line"]:
		var p: String = _reply_naming_her_in(slot)
		if p.find(str(slot)) == -1 and p.find(HER) == -1:
			fail_test("CONTROL: '%s' fixture did not reach the prompt" % slot)
			continue
		if p.find(NOTE) == -1:
			missing.append(str(slot))
	assert_eq(missing, ([] as Array[String]),
		"she is named in these slots and the prompt says nothing about her pronoun: %s"
			% ", ".join(missing))


func test_the_combined_reply_reads_its_blocks_too() -> void:
	## Where 5 of the 8 misgendered samples came from — it writes the reply AND
	## three player choices, so it pronominalises her far more often.
	for block in ["events", "memory", "quest"]:
		var events: Array = NEUTRAL_EVENTS
		var quest: Array = NEUTRAL_QUEST
		var memory: Array = NEUTRAL_MEMORY
		match block:
			"events":
				events = [{"type": "story", "summary": "%s's banners went up." % HER}]
			"memory":
				memory = ["the player asked about %s last time" % HER]
			"quest":
				quest = ["%s has summoned the council again" % HER]
		var p: String = DP.build_combined_reply("Elder Theron", PERSONA, "Harmonia",
			events, NEUTRAL_LAST, NEUTRAL_SAID, 3, quest, {}, memory, "evening")
		assert_true(p.find(NOTE) != -1,
			"the combined path drops her pronoun when only the %s block names her" % block)


func test_the_choice_builder_carries_a_note_at_all() -> void:
	## This path had NONE. Its choices are what the player clicks, so a guessed
	## pronoun ships as a menu row: "Can we reason with him?"
	var by_line: String = DP.build_player_choices("Elder Theron",
		"%s will hear of this." % HER, 3, NEUTRAL_EVENTS)
	assert_true(by_line.find(NOTE) != -1,
		"a choice prompt quoting a line about her must carry her pronoun")
	var by_events: String = DP.build_player_choices("Elder Theron", "Dark days.", 3,
		[{"type": "story", "summary": "%s's banners went up." % HER}])
	assert_true(by_events.find(NOTE) != -1,
		"and so must one whose events name her")


# ── it must not fire on a conversation that never names her ───────────────────

func test_a_conversation_that_never_names_her_carries_no_note() -> void:
	## CORRECT-WORK. The note exists so the prompt does NOT carry a roster the
	## model reads past every turn; scanning more text must not start one.
	var prompts: Dictionary = {
		"opening": DP.build_npc_opening("Elder Theron", PERSONA, "Harmonia",
			NEUTRAL_EVENTS, NEUTRAL_QUEST, "evening", {}, NEUTRAL_MEMORY),
		"reply": DP.build_npc_reply("Elder Theron", PERSONA, "Harmonia",
			NEUTRAL_EVENTS, NEUTRAL_LAST, NEUTRAL_SAID,
			NEUTRAL_QUEST, "evening", {}, NEUTRAL_MEMORY),
		"combined": DP.build_combined_reply("Elder Theron", PERSONA, "Harmonia",
			NEUTRAL_EVENTS, NEUTRAL_LAST, NEUTRAL_SAID, 3,
			NEUTRAL_QUEST, {}, NEUTRAL_MEMORY, "evening"),
		"choices": DP.build_player_choices("Elder Theron", NEUTRAL_LAST, 3, NEUTRAL_EVENTS),
	}
	for name in prompts:
		assert_eq(str(prompts[name]).find("uses she/her"), -1,
			"'%s' grew a pronoun line for a figure nobody mentioned" % name)


func test_the_neutral_fixture_really_renders_every_block() -> void:
	## CONTROL for the arm above, and the failure this file's sibling already hit:
	## a block that silently vanishes gives the same clean "no note" as a correct
	## one. Assert the blocks are THERE and simply carry nobody's name.
	var p: String = DP.build_npc_reply("Elder Theron", PERSONA, "Harmonia",
		NEUTRAL_EVENTS, NEUTRAL_LAST, NEUTRAL_SAID,
		NEUTRAL_QUEST, "evening", {}, NEUTRAL_MEMORY)
	for heading in ["Recent events:", "You have spoken with this traveler before",
			"This character has recently said things like:", "Time of day:"]:
		assert_true(p.find(heading) != -1,
			"the neutral prompt is missing its %s block — the clean result proves nothing" % heading)


# ── shape ─────────────────────────────────────────────────────────────────────

func test_she_is_named_once_however_many_blocks_mention_her() -> void:
	## Scanning the whole body must not repeat the line per mention: the note is
	## one sentence about a fact, and three copies of it is prompt noise the model
	## reads past.
	var p: String = DP.build_npc_reply(HER, "A clerk appointed by %s." % HER, "Harmonia",
		[{"type": "story", "summary": "%s's banners went up." % HER}],
		"%s will hear of this." % HER, "What does %s want?" % HER,
		["%s summoned the council" % HER], "evening", {},
		["the player asked about %s last time" % HER])
	assert_eq(p.count(NOTE), 1, "the pronoun note must appear exactly once")


func test_the_note_still_lands_after_the_output_format_rule() -> void:
	## Position is the one thing the rewrite could have moved: the note has always
	## been the last line, after the JSON rule, and every live measurement in this
	## file and its sibling was taken with it there.
	var p: String = _reply_naming_her_in("player_line")
	var json_at: int = p.find("Respond with ONLY valid JSON")
	assert_true(json_at != -1, "CONTROL: the output rule must still be present")
	assert_gt(p.find(NOTE), json_at, "the note must stay after the output rule, where it was measured")


func test_an_event_the_model_cannot_see_does_not_trigger_it() -> void:
	## The one case this narrows, pinned deliberately. The opening used to scan the
	## RAW event list; _format_events renders only the last CONTEXT_EVENTS, so a
	## figure named further back produced a note about someone the model never
	## reads. Unreachable in production — all five call sites pass exactly
	## CONTEXT_EVENTS — and the direction is right: the note answers a question the
	## prompt raises, so it belongs to the text the model actually gets.
	var events: Array = [{"type": "story", "summary": "%s's banners went up." % HER}]
	for i in DP.CONTEXT_EVENTS:
		events.append({"type": "battle", "summary": "The party cleared a nest of bats."})
	var p: String = DP.build_npc_opening("Elder Theron", PERSONA, "Harmonia", events)
	assert_eq(p.find(HER), -1,
		"CONTROL: the fixture must push her name past the render limit")
	assert_eq(p.find("uses she/her"), -1,
		"a figure the rendered prompt never names must not get a pronoun line")
