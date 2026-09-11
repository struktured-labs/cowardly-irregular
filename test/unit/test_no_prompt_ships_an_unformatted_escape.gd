extends GutTest

## Two prompts told the model "25%%" and "±15%%".
##
## `%%` is the escape for a literal percent in a GDScript format string — but only
## when the string is actually passed through `%`. These two were plain returns:
##
##     DialoguePrompts._party_line_event_hint  "You just dropped below 25%% HP."
##     RebalanceDaemon.build_prompt            "Stay subtle (±15%% max)."
##
## so the escape never resolved and the model read a malformed number. Their own
## siblings are correct — `"...took a chunky hit (%d damage)" % amt` formats, and
## `"HP %d%%" % [...]` resolves — which is what makes this hard to see by reading:
## the file is full of `%%` that is right, and the two that are wrong look identical.
##
## ⚠️ NO BEHAVIOURAL CLAIM. I did not measure that llama3 answers differently to
## "25%%" than to "25%"; a model will usually cope. This is prompt text being
## objectively wrong, cheap to fix, and a class that recurs silently — not a
## measured quality win, and it should not be reported as one.
##
## DRIVEN, NOT SCANNED. A source scan for `%%` has to decide whether a `%` operator
## applies, and it sits on the NEXT line in RuleComposer's two correct cases. So
## this renders the real prompts and asserts what the model actually receives,
## which no reformatting can slip past.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const RD := preload("res://src/llm/RebalanceDaemon.gd")

const EVENT_KINDS: Array[String] = [
	"turn_start", "low_hp", "big_hit_taken", "used_signature_ability", "victory",
]


func _party_ctx(kind: String) -> Dictionary:
	return {
		"event_kind": kind, "speaker_name": "Rilla", "speaker_job_id": "cleric",
		"speaker_hp_pct": 18.0, "speaker_mp_pct": 40.0,
		"speaker_status": [], "speaker_personality": "Cautious",
		"party": [{"name": "Bram", "job_id": "fighter", "hp_pct": 60.0}],
		"enemies": [{"name": "Cave Rat King", "hp_pct": 30.0}],
		"recent_actions": ["Bram attacked"],
		"event_data": {"damage": 340, "ability_id": "cura"},
	}


## Every prompt this lane sends, as the model receives it.
func _rendered() -> Dictionary:
	var out: Dictionary = {}
	for kind in EVENT_KINDS:
		out["party_line/" + kind] = DP.build_party_line(
			"Rilla, cleric. Mercy is a ledger.", ["Stitched. Logged. Forgiven."], _party_ctx(kind))
	out["boss_intent"] = DP.build_boss_intent("Chancellor Mordaine", {
		"persona": "The usurper.", "phase": 2,
		"boss_hp_pct": 48.0, "boss_mp_pct": 70.0, "boss_ap": 2,
		"party": [{"name": "Rilla", "job_id": "cleric", "hp_pct": 22.0, "is_alive": true}],
		"available_intents": ["aggress", "turtle"],
	})
	out["npc_opening"] = DP.build_npc_opening(
		"Elder Theron", "keeper of records", "Harmonia",
		[{"type": "battle", "summary": "The party defeated the Cave Rat King."}])
	out["npc_reply"] = DP.build_npc_reply(
		"Elder Theron", "keeper of records", "Harmonia",
		[{"type": "battle", "summary": "The party defeated the Cave Rat King."}],
		"You came back.", "What happened here?")
	out["rule_composition"] = DP.build_rule_composition(
		"autobattle", "heal when we are hurt", [])
	var d = RD.new()
	out["rebalance"] = d.build_prompt(RD.TRIGGER_BOSS_DEFEAT, {"battles_won": 12}, [])
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_no_prompt_reaches_the_model_with_an_unresolved_escape() -> void:
	## THE ARM. `%%` in rendered output means a format string was never formatted.
	var offenders: Array[String] = []
	for name in _rendered():
		if str(_rendered()[name]).find("%%") != -1:
			offenders.append(str(name))
	assert_eq(offenders, ([] as Array[String]),
		"these prompts ship an unresolved %%%% to the model: %s" % ", ".join(offenders))


func test_the_low_hp_hint_states_a_real_percentage() -> void:
	## The specific instance, pinned by value so a re-escape is named.
	var p: String = DP.build_party_line("a cleric", [], _party_ctx("low_hp"))
	assert_true(p.find("below 25% HP") != -1,
		"the low-hp hint must state 25%% as a number the model can read")


func test_the_rebalance_prompt_states_a_real_bound() -> void:
	var d = RD.new()
	var p: String = str(d.build_prompt(RD.TRIGGER_BOSS_DEFEAT, {"battles_won": 12}, []))
	assert_true(p.find("±15% max") != -1,
		"the daemon's subtlety bound must be a readable percentage")


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_corpus_is_really_populated() -> void:
	## CONTROL: the arm loops rendered prompts, so an empty or tiny set makes it
	## vacuous — the failure direction that reads as clean.
	var r: Dictionary = _rendered()
	assert_gte(r.size(), 10, "expected every builder in the lane, not a subset")
	for name in r:
		assert_gt(str(r[name]).length(), 120,
			"'%s' rendered almost nothing — the builder failed rather than the check passing" % name)


func test_formatting_really_happens_in_these_prompts() -> void:
	## CONTROL, and it is the load-bearing one: absence of `%%` is also what you
	## get from a prompt that contains no percentages at all. Pin that a FORMATTED
	## percentage actually reaches the output, so the arm above is measuring
	## resolution rather than absence.
	var p: String = DP.build_boss_intent("Mordaine", {
		"persona": "x", "phase": 1, "boss_hp_pct": 48.0, "boss_mp_pct": 70.0, "boss_ap": 2,
		"party": [{"name": "Rilla", "job_id": "cleric", "hp_pct": 22.0, "is_alive": true}],
		"available_intents": ["aggress"],
	})
	assert_true(p.find("HP 48%") != -1, "a formatted percentage must render as a number plus one %")
	assert_true(p.find("22%") != -1, "and the party row's percentage too")
