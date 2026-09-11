extends GutTest

## Add a boss persona with intents and LLM strategy silently ignores it.
##
## `_should_use_llm_strategy` gates on a hand-written ALLOWLIST of five. The
## existing guard hand-lists the same five and, for the negative side, checks
## only keys that do not exist ("boss_rat_king", "non_existent_boss", ""). So it
## proves an UNKNOWN key goes deterministic. It never asks what happens to a
## persona that IS eligible and IS absent from the list.
##
## Five are in exactly that state today — the spotlight duel opponents carry a
## persona block and scripted_intents, the only two fields the intent path reads,
## and appear in neither list. Their exclusion is correct and was untested, which
## is the same shape as cowir-battle's speed_demon guard: green for a reason
## nobody chose.
##
## NOT DERIVED, DELIBERATELY. I looked for a data property that separates the two
## groups and the honest answer is that none does: `verbs`, `automation_lines`
## and `jailbreak_vulnerabilities` split them perfectly, but they feed the taunt,
## automation-awareness and jailbreak surfaces — not this gate. Pinning on them
## would be a coincidence dressed as a rule. The list is a design choice, so this
## guard makes the choice EXPLICIT rather than inventing a derivation for it.
##
## The requirement is a REASON, never a skip flag: you cannot silence this green,
## only explain it green, and the explanation is the deliverable.

const BOSS_DIALOGUE_PATH := "res://data/boss_dialogue.json"

## The five W1 roster bosses whose strategic intent is LLM-refinable.
const SHOWCASE: Array[String] = [
	"chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis",
]

## One authored sentence, not five checkboxes — they are excluded for one reason.
const DUEL_OPPONENT_REASON := (
	"Spotlight-duel opponent, not a W1 roster boss: a teaching duel with a fixed "
	+ "lesson, and 2-3 intents against the bosses' 9 give an LLM nothing to choose "
	+ "between. Eligible by data; excluded by design."
)

const EXCLUDED: Dictionary = {
	"fighter_skeleton_knight": DUEL_OPPONENT_REASON,
	"cleric_survive_target": DUEL_OPPONENT_REASON,
	"rogue_lockward": DUEL_OPPONENT_REASON,
	"mage_prismatic_construct": DUEL_OPPONENT_REASON,
	"bard_hostile_courtier": DUEL_OPPONENT_REASON,
}


## Personas the intent path could actually drive: a persona string to speak with
## and at least one scripted intent to choose from. Those are the only two fields
## _build_boss_intent_context reads, so this is the real eligibility test.
func _eligible() -> Array[String]:
	var txt: String = FileAccess.get_file_as_string(BOSS_DIALOGUE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return []
	var root: Dictionary = parsed as Dictionary
	var bosses: Dictionary = root.get("bosses", root) as Dictionary
	var out: Array[String] = []
	for key in bosses:
		var entry: Variant = bosses[key]
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry as Dictionary
		if str(e.get("persona", "")).is_empty():
			continue
		if (e.get("scripted_intents", []) as Array).is_empty():
			continue
		out.append(str(key))
	out.sort()
	return out


func _bm_gs() -> Array:
	return [get_node_or_null("/root/BattleManager"), get_node_or_null("/root/GameState")]


# ── the defect ────────────────────────────────────────────────────────────────

func test_every_eligible_persona_is_classified() -> void:
	## THE ARM. A persona added to boss_dialogue.json with intents is either on
	## the showcase list or explicitly excluded. Neither means it went
	## deterministic and nobody decided that.
	var unclassified: Array[String] = []
	for pid in _eligible():
		if not (pid in SHOWCASE) and not EXCLUDED.has(pid):
			unclassified.append(pid)
	assert_eq(unclassified, ([] as Array[String]),
		"eligible persona(s) in neither list — add to BattleManager's ALLOWLIST, or to EXCLUDED with a reason: %s"
			% ", ".join(unclassified))


func test_the_gate_agrees_with_the_classification() -> void:
	## Drives the REAL function rather than reading its source, so a lookup-shaped
	## rewrite of the gate cannot walk past this the way a literal scan would.
	var pair: Array = _bm_gs()
	var bm = pair[0]
	var gs = pair[1]
	if bm == null or gs == null or not bm.has_method("_should_use_llm_strategy"):
		fail_test("BattleManager/GameState autoload or the gate is missing — a real break")
		return
	var prior: bool = gs.boss_llm_strategy_enabled
	gs.boss_llm_strategy_enabled = true
	for pid in _eligible():
		var routed: bool = bm._should_use_llm_strategy(pid)
		if pid in SHOWCASE:
			assert_true(routed, "%s is declared showcase but the gate refuses it" % pid)
		elif EXCLUDED.has(pid):
			assert_false(routed, "%s is declared excluded but the gate routes it to the LLM" % pid)
	gs.boss_llm_strategy_enabled = prior


# ── the declarations must not go stale ────────────────────────────────────────

func test_no_declaration_names_a_persona_that_is_gone() -> void:
	## The other direction: a renamed or deleted persona must not leave a name
	## here claiming to classify something. That is how a list starts lying.
	var live: Array[String] = _eligible()
	for pid in SHOWCASE:
		assert_true(pid in live, "SHOWCASE names '%s', which is no longer an eligible persona" % pid)
	for pid in EXCLUDED:
		assert_true(str(pid) in live, "EXCLUDED names '%s', which is no longer an eligible persona" % pid)


func test_every_exclusion_carries_a_real_reason() -> void:
	## A reason is the DELIVERABLE. A blank or token string would make this a
	## skip flag, which is rot arriving dressed as diligence.
	for pid in EXCLUDED:
		var why: String = str(EXCLUDED[pid])
		assert_gt(why.length(), 40,
			"'%s' must carry an explanation, not a token — you explain this green, you cannot silence it" % pid)


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_eligible_set_is_really_populated() -> void:
	## CONTROL: every assert above is vacuous on an empty set. A parse failure or
	## a moved "bosses" key would otherwise read as total agreement.
	var live: Array[String] = _eligible()
	assert_gte(live.size(), 8,
		"expected the five W1 bosses plus the duel opponents — a small set here means the parse failed, not that the data shrank")
	assert_true("chancellor_mordaine" in live, "the showcase boss must be eligible, or the field names changed")


func test_the_flag_still_switches_the_whole_feature_off() -> void:
	## CONTROL: this file asserts routing decisions, which are meaningless if the
	## opt-in is stuck on. Pins that the classification is read UNDER the flag.
	var pair: Array = _bm_gs()
	var bm = pair[0]
	var gs = pair[1]
	if bm == null or gs == null:
		fail_test("BattleManager/GameState autoload missing — a real break")
		return
	var prior: bool = gs.boss_llm_strategy_enabled
	gs.boss_llm_strategy_enabled = false
	for pid in SHOWCASE:
		assert_false(bm._should_use_llm_strategy(pid),
			"with the opt-in OFF even %s must stay deterministic" % pid)
	gs.boss_llm_strategy_enabled = prior
