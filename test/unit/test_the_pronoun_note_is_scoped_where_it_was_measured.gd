extends GutTest

## Two live prompts name Chancellor Mordaine and carry no pronoun note. I added
## it to both, measured, and took it back out.
##
## An hour ago the note was routed through the assembled prompt so no context
## block could name a figure without it firing
## (test_the_pronoun_note_reads_the_whole_prompt). That covered the four NPC
## conversation builders. Two more name her and were never scanned:
##
##     build_party_line    Enemies: "  - Chancellor Mordaine: HP 44%"
##     build_npc_sign_off  the conversation tail, which is its whole input
##
## That reads like the same gap. It is not, and the difference is measurable.
##
## ══ MEASURED, live llama3, on the real prompts ═══════════════════════════════
##
##   party lines (turn_start · big_hit_taken · used_signature_ability · victory,
##   five jobs) and farewells, Mordaine named in every prompt:
##
##     arm                                samples   gendered   wrong   right
##     shipped (no note)                    176         1        1       0
##     note appended (what I nearly shipped)176         5        4       1
##     "(she/her)" inline in the roster      64         0        0       0
##
##   For contrast, the SAME note on the conversation builders, same model:
##     shipped 6 of 6 gendered references WRONG · with the note 13 of 13 RIGHT
##
## ⛔ THE DEFECT DOES NOT EXIST ON THESE TWO PATHS. One gendered pronoun in 176
## shipped samples — a party line is one short utterance and every event hint is
## self-facing ("react", "flex or downplay it", "say something before you act"),
## so the enemy is named and almost never pronominalised. A farewell is a closed
## form. There is nothing for the note to correct.
##
## ⚠️ AND A RETRACTION I ALMOST PUBLISHED. My first run showed 3 misgendered in
## the appended arm against 0 shipped, and I had written it up as "the note
## INDUCES the error it prevents." It did not replicate: the same prompts at the
## same n gave 0 gendered in that arm and 1 in shipped. 4 against 1 across 176 is
## noise (Fisher p ≈ 0.4), not a mechanism. The honest result is a null in both
## directions, and the first write-up would have put a causal claim into a file
## nobody re-measures.
##
## ══ SO THIS FILE IS THE DELIVERABLE, AND THE SOURCE IS UNCHANGED ═════════════
##
## Every builder is classified with the reason behind its classification. The
## corpus is DERIVED from `static func build_` in the source, so a builder added
## tomorrow reds this file until someone decides — and the WITHHELD arm is the
## point: it stops the next reader "completing the coverage" on a gap that was
## measured and found empty. That loop is not hypothetical. The sign-off's own
## docstring exists because its missing context blocks were re-opened as a bug
## TWICE after being measured and rejected.

const DP := preload("res://src/llm/DialoguePrompts.gd")

const HER := "Chancellor Mordaine"
const NOTE := "Chancellor Mordaine uses she/her"
const SRC := "res://src/llm/DialoguePrompts.gd"

## Prose a player reads, long enough to pronominalise a third party. Measured:
## 6 of 6 gendered references wrong without the note, 13 of 13 right with it.
const CARRIES: Array[String] = [
	"build_npc_opening", "build_npc_opening_topical", "build_npc_reply",
	"build_combined_reply", "build_player_choices",
]

## Names her, and measured NOT to need it. Adding it is the change to resist.
const WITHHELD: Dictionary = {
	"build_party_line":
		"1 gendered pronoun in 176 samples — one short self-facing utterance per event",
	"build_npc_sign_off":
		"a farewell is a closed form; 0 gendered in 28 samples with the note and without",
}

## Output is not prose at all.
const EXEMPT: Dictionary = {
	"build_boss_intent":
		"returns an intent enum and posture — the boss's choice, never a spoken line",
	"build_rule_composition":
		"returns autobattle rules; its inputs are ability ids and the player's own rule text",
}


func _events_naming_her() -> Array:
	return [{"type": "story", "summary": "%s sealed the castle gates." % HER}]


func _party_ctx() -> Dictionary:
	return {
		"event_kind": "victory",
		"speaker_name": "Kesh", "speaker_job_id": "rogue",
		"speaker_hp_pct": 52.0, "speaker_mp_pct": 40.0,
		"speaker_status": [], "speaker_personality": "",
		"party": [{"name": "Kesh", "job_id": "rogue", "hp_pct": 52.0, "is_alive": true}],
		"enemies": [{"name": HER, "hp_pct": 0.0}],
		"recent_actions": [{"actor": HER, "ability_id": "verdict", "damage": 90}],
		"event_data": {},
	}


## Each builder driven with her named in an input it really receives in production.
func _drive(builder: String) -> String:
	match builder:
		"build_npc_opening":
			return DP.build_npc_opening("Elder Theron", "keeper of records", "Harmonia",
				_events_naming_her())
		"build_npc_opening_topical":
			return DP.build_npc_opening_topical("Elder Theron", "keeper of records",
				"Harmonia", "the sealed gates", _events_naming_her())
		"build_npc_reply":
			return DP.build_npc_reply("Elder Theron", "keeper of records", "Harmonia",
				_events_naming_her(), "Dark days.", "What now?")
		"build_combined_reply":
			return DP.build_combined_reply("Elder Theron", "keeper of records", "Harmonia",
				_events_naming_her(), "Dark days.", "What now?", 3)
		"build_player_choices":
			return DP.build_player_choices("Elder Theron", "Dark days.", 3,
				_events_naming_her())
		"build_npc_sign_off":
			return DP.build_npc_sign_off("Elder Theron", "keeper of records", "Harmonia",
				_events_naming_her(), "%s does not forgive debts." % HER,
				"Will the Chancellor go through with it?")
		"build_party_line":
			return DP.build_party_line("A rogue who counts exits.", ["Told you."], _party_ctx())
	return ""


## Every `static func build_*` declared in the source — the corpus, derived.
func _declared_builders() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SRC)
	var out: Array[String] = []
	for line in src.split("\n"):
		if not line.begins_with("static func build_"):
			continue
		var rest: String = line.substr("static func ".length())
		var paren: int = rest.find("(")
		if paren > 0:
			out.append(rest.substr(0, paren))
	return out


# ── the classification must cover the corpus ──────────────────────────────────

func test_every_declared_builder_is_classified() -> void:
	## The ratchet. A hand-named list is how the last guard covered four builders
	## and could not see the two it did not name.
	var declared: Array[String] = _declared_builders()
	assert_gte(declared.size(), 8,
		"CONTROL: the source scan derived only %d builders — the derivation is broken" % declared.size())
	var unclassified: Array[String] = []
	for b in declared:
		if CARRIES.has(b) or WITHHELD.has(b) or EXEMPT.has(b):
			continue
		unclassified.append(b)
	assert_eq(unclassified, ([] as Array[String]),
		"unclassified builders — decide and write the reason: %s" % ", ".join(unclassified))


func test_the_classification_has_not_gone_stale() -> void:
	## The other direction: an entry for a builder that no longer exists lets the
	## arm above pass for a corpus that shrank underneath it.
	var declared: Array[String] = _declared_builders()
	var ghosts: Array[String] = []
	for b in CARRIES:
		if not declared.has(b):
			ghosts.append(b)
	for d in [WITHHELD, EXEMPT]:
		for b in d:
			if not declared.has(str(b)):
				ghosts.append(str(b))
	assert_eq(ghosts, ([] as Array[String]),
		"classified builders that no longer exist: %s" % ", ".join(ghosts))


func test_every_withheld_and_exempt_builder_states_its_reason() -> void:
	## You explain a classification here; you cannot flag one.
	for d in [WITHHELD, EXEMPT]:
		for b in d:
			assert_gt(str(d[b]).length(), 30,
				"'%s' is classified with no usable reason" % str(b))


# ── the classification must match what the builders do ────────────────────────

func test_conversation_prose_carries_her_pronoun() -> void:
	## Where the note was measured to work: 6 of 6 wrong without it, 13 of 13 right with.
	var missing: Array[String] = []
	for b in CARRIES:
		var p: String = _drive(b)
		if p.length() < 100:
			fail_test("CONTROL: '%s' rendered almost nothing — the driver is wrong" % b)
			continue
		if p.find(HER) == -1:
			fail_test("CONTROL: '%s' fixture never names her, so it proves nothing" % b)
			continue
		if p.find(NOTE) == -1:
			missing.append(b)
	assert_eq(missing, ([] as Array[String]),
		"these speak about her and never say she: %s" % ", ".join(missing))


func test_the_withheld_builders_really_withhold_it() -> void:
	## ⛔ THE ARM THAT RESISTS THE CHANGE. Both prompts name her, so the gap is
	## visible to anyone reading them and looks exactly like the one that WAS a
	## defect. If this reds because someone added the note, re-measure first —
	## the numbers to beat are in this file's header.
	var added: Array[String] = []
	for b in WITHHELD:
		var p: String = _drive(str(b))
		if p.find(HER) == -1:
			fail_test("CONTROL: '%s' fixture must name her, or the absence proves nothing" % str(b))
			continue
		if p.find("uses she/her") != -1:
			added.append(str(b))
	assert_eq(added, ([] as Array[String]),
		"the note was added to a path measured not to need it: %s" % ", ".join(added))


# ── controls ──────────────────────────────────────────────────────────────────

func test_a_conversation_that_never_names_her_carries_no_note() -> void:
	## CORRECT-WORK for the CARRIES set: the note must not become a roster the
	## model reads past every turn.
	var p: String = DP.build_npc_reply("Elder Theron", "keeper of records", "Harmonia",
		[{"type": "battle", "summary": "The party defeated the Cave Rat King."}],
		"Fine weather.", "Where can I buy rope?")
	assert_true(p.find("Cave Rat King") != -1, "CONTROL: the events block must render")
	assert_eq(p.find("uses she/her"), -1, "no figure mentioned means no pronoun line")


func test_the_party_line_fixture_is_the_shape_battle_supplies() -> void:
	## CONTROL: the withheld arm is an ASSERTION OF ABSENCE, so its fixture has to
	## be the real one. BattleManager fills enemies from combatant_name, and
	## monsters.json names her "Chancellor Mordaine".
	var p: String = _drive("build_party_line")
	assert_true(p.find("Enemies:") != -1, "the enemy block must render")
	assert_true(p.find("  - %s: HP" % HER) != -1,
		"the roster must carry her name the way BattleManager writes it")


func test_the_sign_off_still_refuses_the_shared_context_blocks() -> void:
	## CONTROL on the neighbouring decision this file sits beside — the one that
	## was re-opened twice. If it ever changes, this file's reasoning changes too.
	var p: String = _drive("build_npc_sign_off")
	for heading in ["Time of day:", "You have spoken with this traveler before",
			"This character has recently said things like:"]:
		assert_eq(p.find(heading), -1,
			"the sign-off grew a %s block — that was measured and rejected" % heading)
