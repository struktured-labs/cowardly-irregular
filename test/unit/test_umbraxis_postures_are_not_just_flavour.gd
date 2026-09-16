extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## Umbraxis authored its own names for the three armed postures — null_strike /
## null_field / existential_dread — and NONE of them reached a bias arm, so every
## intent the LLM picked for the W1 shadow dragon was mechanically inert.
##
## It is the one dragon this can be fixed for by the table alone: _ai_caster is
## the only ladder that reads attack_weight, and of the four dragons only Umbraxis
## classifies as a caster (Pyrroth/Glacius are tanks, Voltharion an assassin).
## Arming the other three's names would advertise a posture that still does
## nothing — a ladder change, not a table one.
##
## Measured against llama3 x20 on a defend board (boss 12% HP, 0 AP, party fresh),
## before this fix: the press-the-attack posture won 17/20 with nothing behind it.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const DialoguePromptsScript = preload("res://src/llm/DialoguePrompts.gd")
const ROLLS := 400
const UMBRAXIS := "shadow_dragon"

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)


func _from_data(mid: String) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = int(st.get("max_mp", 9999)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.magic_defense = int(st.get("magic_defense", 10))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c


func _victim() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Party"
	c.max_hp = 5000; c.current_hp = 5000
	return c


func _resolved_kit(boss: Combatant) -> Array:
	var avail: Array = []
	for aid in (boss.job["abilities"] as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	return avail


## Fraction of decisions that were a MAGIC ability, driving the real ladder.
func _magic_rate(mid: String, intent_id: String) -> float:
	var boss := _from_data(mid)
	if intent_id != "":
		boss.set_meta("llm_intent", intent_id)
	var target := _victim()
	var avail: Array = _resolved_kit(boss)
	assert_gt(avail.size(), 0, "CONTROL: %s's kit resolves against abilities.json" % mid)
	var arch: String = _bm._get_ai_archetype(boss, avail)
	assert_eq(arch, "caster",
		"CONTROL: %s must classify as a caster, or this measures the wrong AI arm" % mid)
	var magic: int = 0
	for _i in ROLLS:
		boss.current_mp = boss.max_mp  # isolate the intent from MP exhaustion
		var action: Dictionary = _bm._execute_archetype_ai(boss, arch, avail, [boss], [target])
		if str(action.get("type", "")) == "ability":
			var a: Dictionary = JobSystem.get_ability(str(action.get("ability_id", "")))
			if str(a.get("type", "")) == "magic":
				magic += 1
	return float(magic) / float(ROLLS)


func _authored_intents(bid: String) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_dialogue.json"))
	assert_not_null(parsed, "CONTROL: boss_dialogue.json parses")
	var root: Dictionary = (parsed as Dictionary).get("bosses", parsed)
	var out: Array = []
	for spec in (root.get(bid, {}) as Dictionary).get("scripted_intents", []):
		if spec is Dictionary:
			out.append(str((spec as Dictionary).get("id", "")))
	return out


# ── the fix, measured on the real decision path ───────────────────────────────

func test_umbraxis_casts_more_under_its_own_aggressive_posture() -> void:
	var pressing: float = _magic_rate(UMBRAXIS, "null_strike")
	var guarding: float = _magic_rate(UMBRAXIS, "null_field")
	gut.p("  umbraxis magic rate — null_strike %.3f · null_field %.3f" % [pressing, guarding])
	assert_gt(pressing, guarding,
		"the shadow dragon must cast MORE under its press posture than its guard posture")
	assert_gt(pressing - guarding, 0.15,
		"and the gap must be a mechanical swing, not sampling noise (1.4x vs 0.6x on a 0.75 base)")


func test_the_swing_matches_the_posture_it_delegates_to() -> void:
	## Delegation, not a copy: if the two ever drift the LLM's word stops meaning
	## what the table says it means.
	for pair in [["null_strike", "aggress"], ["null_field", "turtle"],
			["existential_dread", "exploit_pattern"]]:
		assert_eq(_bm._bias_by_intent(str(pair[0])), _bm._bias_by_intent(str(pair[1])),
			"%s must carry exactly %s's bias" % [str(pair[0]), str(pair[1])])


func test_an_unknown_intent_is_still_inert() -> void:
	## Discriminator. If any string moved the rate, the swing above would be
	## measuring randomness rather than the table.
	var baseline: float = _magic_rate(UMBRAXIS, "")
	var nonsense: float = _magic_rate(UMBRAXIS, "hokum_pokum")
	gut.p("  umbraxis magic rate — no intent %.3f · nonsense %.3f" % [baseline, nonsense])
	assert_lt(absf(baseline - nonsense), 0.15,
		"an intent the table does not know must fall through to no bias")


func test_the_three_names_are_the_ones_umbraxis_actually_authors() -> void:
	## Pins the fix to the DATA. A renamed intent in boss_dialogue.json reds this
	## rather than silently going inert again.
	var authored: Array = _authored_intents("umbraxis")
	assert_gt(authored.size(), 0, "CONTROL: umbraxis must author scripted_intents")
	for id in ["null_strike", "null_field", "existential_dread"]:
		assert_true(id in authored,
			"%s must still be one of umbraxis's authored intents" % id)
		assert_false(_bm._bias_by_intent(id).is_empty(),
			"%s must reach a bias arm — it is described to the LLM as a working posture" % id)


func test_the_model_can_tell_the_three_apart() -> void:
	## The prompt half. Bare ids are what made the picker a coin flip: the boss's
	## own list rendered as jargon while the one described option was a posture
	## that does something else.
	for id in ["null_strike", "null_field", "existential_dread"]:
		assert_true(DialoguePromptsScript.INTENT_DESCRIPTIONS.has(id),
			"%s must be explained in the intent list" % id)
	var ctx: Dictionary = {
		"persona": "Umbraxis, the Void Render.",
		"phase": 1, "boss_hp_pct": 12.0, "boss_mp_pct": 20.0, "boss_ap": 0,
		"available_intents": ["null_strike", "null_field", "existential_dread"],
	}
	var prompt: String = DialoguePromptsScript.build_boss_intent("Umbraxis", ctx)
	assert_true(prompt.find("null_field: defend and outlast") != -1,
		"the guard posture must say WHEN it applies, not just its name")
	assert_true(prompt.find("null_strike: press the attack") != -1,
		"and so must the aggressive one")


func test_the_other_three_dragons_are_left_alone() -> void:
	## Scope pin. Their ladders read no bias, so arming their names would promise
	## a posture that still does nothing. Reds if someone arms them without
	## moving the ladder too.
	for id in ["scorch", "guard_scales", "deep_freeze", "frost_turtle", "blitz", "static_taunt"]:
		assert_true(_bm._bias_by_intent(id).is_empty(),
			"%s must stay unarmed while its boss's ladder cannot read a bias" % id)
		assert_false(DialoguePromptsScript.INTENT_DESCRIPTIONS.has(id),
			"%s must not be described as a working posture" % id)


func test_the_subject_members_this_file_drives_still_exist() -> void:
	## A guard that reaches its subject by direct call goes SILENT when that subject is
	## renamed: the arm asserts, THEN aborts, so GUT scores it PASSING — not Risky, not
	## Failed. Measured on this file 2026-09-16 by renaming the member it defends: every
	## arm still passed, Failing 0, Risky 0, EC 0, and the ONLY cardinal that moved was
	## the assert count. run_tests.sh's exit 4 cannot see this rung, because these arms
	## DID assert before dying. Derived from this file's own calls, so a new direct call
	## joins the floor without anyone remembering to add it.
	var src: String = GdSource.code_of("res://test/unit/test_umbraxis_postures_are_not_just_flavour.gd")
	assert_false(src.is_empty(), "CONTROL: this file's own source must be readable")
	var builtin := Object.new()
	var want_methods: Array = []
	var re_m := RegEx.create_from_string("\\b_bm\\.(_?[a-z][A-Za-z0-9_]*)\\s*\\(")
	for m in re_m.search_all(src):
		var n: String = m.get_string(1)
		if not builtin.has_method(n) and not want_methods.has(n):
			want_methods.append(n)
	var want_consts: Array = []
	var re_c := RegEx.create_from_string("\\b_bm\\.([A-Z][A-Z0-9_]+)\\b")
	for m in re_c.search_all(src):
		var n: String = m.get_string(1)
		if not want_consts.has(n):
			want_consts.append(n)
	builtin.free()
	assert_gt(want_methods.size() + want_consts.size(), 0,
		"FLOOR: the derivation must find the members this file drives, or it guards nothing")
	assert_not_null(_bm, "CONTROL: the subject must be reachable")
	var consts: Dictionary = _bm.get_script().get_script_constant_map()
	var missing: Array = []
	for n in want_methods:
		if not _bm.has_method(str(n)):
			missing.append(str(n) + "()")
	for n in want_consts:
		if not consts.has(str(n)):
			missing.append(str(n))
	assert_eq(missing, [],
		"the subject no longer has these, so the arms above assert once and then ABORT into a silent pass: %s"
			% str(missing))
