extends GutTest

## Sharing is a shipped pillar: autobattle scripts travel as `COWIR1:` clipboard codes, and the
## receiving end validates them against the engine's grammar before applying. Four conditions were
## added to that grammar today — not_has_status, not_enemy_has_status, enemy_weak_to,
## volatility_band — and each was verified in the editor, the evaluator and the LLM prompt.
##
## NOT verified until now: that a script using them survives a share code. The codec is
## base64(gzip(json)) and the new conditions carry payload fields the older ones do not
## (`element`, and a `value` on a 0..3 scale rather than a percentage), so "it is registered
## therefore it round-trips" is a reasonable expectation and not a measurement. A player who
## composed a rule with one of these and pasted it to a friend is the case that matters.

var _abs: Node = null
var _fixture_ids: Array[String] = []

## One rule per new condition, each carrying the payload shape the grammar gives it.
const NEW_CONDITION_RULES := [
	{"conditions": [{"type": "not_has_status", "status": "shadow_step"}, {"type": "mp_percent", "op": ">=", "value": 18}],
	 "actions": [{"type": "ability", "id": "shadow_step", "target": "self"}], "enabled": true},
	{"conditions": [{"type": "not_enemy_has_status", "status": "blind"}, {"type": "mp_percent", "op": ">=", "value": 14}],
	 "actions": [{"type": "ability", "id": "smoke_bomb", "target": "lowest_hp_enemy"}], "enabled": true},
	{"conditions": [{"type": "enemy_weak_to", "element": "fire"}, {"type": "mp_percent", "op": ">=", "value": 30}],
	 "actions": [{"type": "ability", "id": "summon_ifrit", "target": "lowest_hp_enemy"}], "enabled": true},
	{"conditions": [{"type": "volatility_band", "op": ">=", "value": 2}, {"type": "mp_percent", "op": ">=", "value": 24}],
	 "actions": [{"type": "ability", "id": "press_the_edge", "target": "lowest_hp_enemy"}], "enabled": true},
	{"conditions": [{"type": "always"}],
	 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
]


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_fixture_ids.clear()


func after_each() -> void:
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _install() -> String:
	var cid := "share_probe_hero"
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "New Grammar",
		"rules": NEW_CONDITION_RULES.duplicate(true)})
	return cid


func test_the_grammar_still_accepts_every_new_condition() -> void:
	## The premise. If validate_rule refused one of these the round-trip arms below would fail for
	## a reason that has nothing to do with sharing.
	if _abs == null or not _abs.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	var refused: Array = []
	for r in NEW_CONDITION_RULES:
		var errors: Array = _abs.validate_rule(r)
		if errors.size() > 0:
			refused.append(str(errors))
	assert_eq(refused.size(), 0, "the grammar must accept all four before sharing is the question: " + str(refused))


func test_a_code_carrying_the_new_conditions_survives_the_round_trip() -> void:
	if _abs == null:
		pending("AutobattleSystem autoload required")
		return
	var cid := _install()
	var code: String = ScriptShareManager.encode_share_code(cid)
	assert_true(code.begins_with(ScriptShareManager.SHARE_CODE_PREFIX),
		"CONTROL: a real share code was produced, not an empty string: '%s'" % code.substr(0, 24))

	var decoded: Dictionary = ScriptShareManager.decode_share_code(code)
	assert_false(decoded.is_empty(), "the code must decode back to a script")
	var rules: Array = decoded.get("script", decoded).get("rules", [])
	assert_eq(rules.size(), NEW_CONDITION_RULES.size(),
		"every rule must survive the trip, not just the ones the old grammar knew (%d of %d)"
		% [rules.size(), NEW_CONDITION_RULES.size()])


func test_the_payload_fields_survive_and_not_just_the_type_names() -> void:
	## The half that a shallow check would miss: `enemy_weak_to` without its `element`, or
	## `not_enemy_has_status` without its `status`, decodes to a condition that is permanently
	## false — it would import clean and silently never fire.
	if _abs == null:
		pending("AutobattleSystem autoload required")
		return
	var decoded: Dictionary = ScriptShareManager.decode_share_code(ScriptShareManager.encode_share_code(_install()))
	var rules: Array = decoded.get("script", decoded).get("rules", [])
	var found: Dictionary = {}
	for r in rules:
		for c in ((r as Dictionary).get("conditions", []) as Array):
			var cd: Dictionary = c
			found[str(cd.get("type", ""))] = cd
	for want in [["not_has_status", "status", "shadow_step"], ["not_enemy_has_status", "status", "blind"],
			["enemy_weak_to", "element", "fire"]]:
		var cd: Dictionary = found.get(str(want[0]), {})
		assert_false(cd.is_empty(), "%s must survive the round trip" % str(want[0]))
		assert_eq(str(cd.get(str(want[1]), "")), str(want[2]),
			"%s must keep its '%s' payload, or it imports clean and never fires" % [str(want[0]), str(want[1])])
	var band: Dictionary = found.get("volatility_band", {})
	assert_false(band.is_empty(), "volatility_band must survive the round trip")
	assert_eq(int(band.get("value", -1)), 2,
		"and keep its BAND value — 0..3, not a percentage, so a mangled value is not obviously wrong")


func test_the_receiving_end_accepts_the_decoded_script() -> void:
	## What the importing player actually hits. validate_imported_script is the gate on a stranger's
	## clipboard, and it is the one that would refuse a condition the receiver's build does not know.
	if _abs == null:
		pending("AutobattleSystem autoload required")
		return
	var decoded: Dictionary = ScriptShareManager.decode_share_code(ScriptShareManager.encode_share_code(_install()))
	var script: Dictionary = decoded.get("script", decoded)
	var errors: Array = ScriptShareManager.validate_imported_script(script)
	assert_eq(errors.size(), 0, "a code using the new grammar must import clean: " + str(errors))

	## CONTROL: the validator is not simply returning [] for everything. An unregistered condition
	## must still be refused, or the arm above says nothing about the four that matter.
	var junk: Dictionary = {"rules": [{"conditions": [{"type": "enemy_smells_nice"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]}
	assert_gt(ScriptShareManager.validate_imported_script(junk).size(), 0,
		"CONTROL: an unknown condition must still be refused")


func test_a_refused_code_says_WHY_instead_of_calling_itself_invalid() -> void:
	## Found by the round-trip above rather than by looking for it. A code using a condition this
	## build does not have is WELL FORMED and merely newer — but decode_share_code computed the
	## reason, pushed it to a log the player never reads, and returned {}. Both paste paths see only
	## {} and say "Not a valid share code", which is false about the code and useless to the player.
	## The same defect the appliers were fixed for, still open one layer down, and it stopped being
	## hypothetical the day four conditions joined the grammar.
	var future: Dictionary = {"type": "autobattle_script", "version": 1, "script": {
		"character_id": "from_the_future", "name": "Newer Build", "rules": [
			{"conditions": [{"type": "enemy_is_левша"}],
			 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]}}
	var json: String = JSON.stringify(future)
	var gz: PackedByteArray = json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var code: String = ScriptShareManager.SHARE_CODE_PREFIX + Marshalls.raw_to_base64(gz)

	assert_true(ScriptShareManager.decode_share_code(code).is_empty(),
		"CONTROL: a code whose grammar this build does not know must still be REFUSED, not applied")
	var why: String = ScriptShareManager.last_import_reason()
	assert_ne(why, "",
		"the refusal must carry a reason — it was computed one line before the return and thrown "
		+ "away, so the player was told a well-formed code was 'not a valid share code'")
	assert_true(why.contains("enemy_is_левша"),
		"and the reason must NAME the unknown condition, or it explains nothing: '%s'" % why)


func test_the_reason_cannot_be_a_leftover_from_the_previous_paste() -> void:
	## The half that makes the fix safe rather than merely louder. A stale reason is a CONFIDENT
	## WRONG answer, which is worse than "no reason reported": paste a newer code, get a real
	## explanation, then paste something that is genuinely not a share code at all and be told the
	## previous code's problem.
	var bad_grammar: Dictionary = {"type": "autobattle_script", "version": 1, "script": {
		"rules": [{"conditions": [{"type": "no_such_condition_at_all"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]}}
	var gz: PackedByteArray = JSON.stringify(bad_grammar).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	ScriptShareManager.decode_share_code(ScriptShareManager.SHARE_CODE_PREFIX + Marshalls.raw_to_base64(gz))
	assert_ne(ScriptShareManager.last_import_reason(), "", "CONTROL: that paste set a reason to go stale")

	ScriptShareManager.decode_share_code(ScriptShareManager.SHARE_CODE_PREFIX + "not-base64-at-all!!")
	assert_eq(ScriptShareManager.last_import_reason(), "",
		"a refusal with no computed reason must report NONE, never the previous paste's — a wrong "
		+ "explanation is worse than an absent one")
