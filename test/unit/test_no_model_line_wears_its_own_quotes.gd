extends GutTest

## The capture of the Prismatic Construct's last words (2026-10-31) showed the model wrapping its whole reply in
## quotes despite every prompt saying not to: the box printed the marks and the battle log doubled them (""…"").
## a6d3e0e3f fixed it for the boss gloat only. The same model writes six other kinds of line a player reads (NPC
## openings, replies, the reply menu, boss taunts, party combat lines, the rule composer's name and description),
## and every one reached the screen through a bare strip_edges().
##
## So the rule lives ONCE, in DialoguePrompts.clean_model_text, and every validator routes its display text through
## it. The coverage arm DERIVES the validator list from source, so a validator added later reds here until it is
## either driven below or exempted with a reason. A hand list would go stale the day someone added one.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const DP_PATH := "res://src/llm/DialoguePrompts.gd"
const Q := "\"Pass.\""
const CLEAN := "Pass."
## Exempt validators, each with its reason. Empty today: every validator returns text a player reads.
const EXEMPT := {}


const DRIVEN: Array[String] = [
	"validate_npc_opening", "validate_player_choices", "validate_npc_reply", "validate_combined_reply",
	"validate_boss_intent", "validate_party_line", "validate_rule_composition",
]


## Each validator, fed a model reply with its display text wrapped in quotes, returns the display strings it produced.
func _outputs_for(name: String) -> Array:
	match name:
		"validate_npc_opening":
			return [DP.validate_npc_opening({"line": Q})["line"]]
		"validate_player_choices":
			return DP.validate_player_choices({"choices": ["\"Ask about the map.\"", "\"Leave.\"", "\"Stay.\""]}, 3)["choices"]
		"validate_npc_reply":
			return [DP.validate_npc_reply({"line": Q})["line"]]
		"validate_combined_reply":
			var v: Dictionary = DP.validate_combined_reply({"reply": Q, "choices": ["\"Leave.\""]}, 1)
			return [v["reply"]] + (v["choices"] as Array)
		"validate_boss_intent":
			return [DP.validate_boss_intent({"intent_id": "aggress", "taunt": Q}, ["aggress"])["taunt"]]
		"validate_party_line":
			return [DP.validate_party_line({"line": Q, "mood": "neutral"})["line"]]
		"validate_rule_composition":
			var r: Dictionary = DP.validate_rule_composition({"name": Q, "description": Q, "rules_json": "[]"}, "autobattle")
			return [r["name"], r["description"]]
	return []


func _derived_validators() -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("(?m)^static func (validate_[a-z_]+)\\(")
	for m in rx.search_all(FileAccess.get_file_as_string(DP_PATH)):
		out.append(m.get_string(1))
	out.sort()
	return out


func test_every_validator_is_driven_or_exempted() -> void:
	var derived: Array = _derived_validators()
	assert_gt(derived.size(), 6, "FLOOR: derived only %s, so the source scan broke and every arm here is vacuous" % [derived])
	var driven: Array = DRIVEN
	for name in derived:
		assert_true(driven.has(name) or EXEMPT.has(name),
			"%s returns model text and is neither driven by this file nor exempted with a reason" % name)
	for name in driven:
		assert_true(derived.has(name), "%s is driven here but no longer exists — a stale row" % name)


func test_no_validator_lets_the_models_own_quotes_through() -> void:
	## THE DEFECT, on every surface at once.
	for name in DRIVEN:
		var outs: Array = _outputs_for(name)
		assert_gt(outs.size(), 0, "%s produced no display text to judge, so its arm is vacuous" % name)
		for text in outs:
			var t: String = str(text)
			assert_false(t.begins_with("\"") or t.ends_with("\""), "%s let the model's wrapping quotes reach the screen: %s" % [name, t])
	assert_eq(DP.validate_npc_reply({"line": Q})["line"], CLEAN, "and the text inside is kept, exactly")


func test_control_an_unquoted_line_passes_through_unchanged() -> void:
	## CONTROL: the arm above also passes on a validator that mangles every line; this one does not.
	assert_eq(DP.validate_party_line({"line": CLEAN, "mood": "neutral"})["line"], CLEAN, "a clean party line is untouched")
	assert_eq(DP.validate_npc_opening({"line": CLEAN})["line"], CLEAN, "a clean opening is untouched")
	var speech := "He said \"no\" and walked off."
	assert_eq(DP.validate_party_line({"line": speech, "mood": "neutral"})["line"], speech,
		"quoted speech INSIDE a line is the model writing dialogue, not wrapping it, and must stay")


func test_the_boss_intent_id_is_not_cleaned_as_text() -> void:
	## intent_id is an identifier matched against the available set, not a line anyone reads.
	var v: Dictionary = DP.validate_boss_intent({"intent_id": "aggress", "taunt": Q}, ["aggress"])
	assert_eq(str(v["intent_id"]), "aggress", "the intent survives validation untouched")
	assert_eq(str(v["taunt"]), CLEAN, "while its taunt loses the wrapping quotes")


func test_only_a_matched_outer_pair_is_removed() -> void:
	var cases := {
		"\"Pass.\"": "Pass.", "“Pass.”": "Pass.", "  \"Pass.\"  ": "Pass.",
		"The Construct stills. 'You matched each face.'": "The Construct stills. 'You matched each face.'",
		"He said \"no\" and fell.": "He said \"no\" and fell.",
		"\"Mismatched.”": "\"Mismatched.”", "\"": "\"", "": "",
	}
	for raw in cases:
		assert_eq(DP.clean_model_text(str(raw)), str(cases[raw]), "clean_model_text(%s)" % JSON.stringify(raw))


func test_the_gloat_uses_the_same_rule() -> void:
	## One implementation: BattleManager's gloat helper must agree with the canonical rule on every case, or two
	## copies are drifting.
	for raw in ["\"Pass.\"", "“Pass.”", "He said \"no\" and fell.", "\"Mismatched.”", "plain"]:
		assert_eq(BattleManager.strip_wrapping_quotes(raw), DP.clean_model_text(raw),
			"the gloat's quote rule and the canonical one disagree on %s" % JSON.stringify(raw))
