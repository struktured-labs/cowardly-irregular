extends GutTest

## Umbraxis announced "Null Field" and then cast it LESS: the posture's turtle alias cut his casting to 0.45 and the
## 1.5x bias only scaled a 1/6 slot. The named spell now takes the top slot and is exempt from the posture's cast cut.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const TURNS := 3000
const SEED := 8061
const NULL_FIELD_SET := ["null_field", "shadow_bind"]

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _monsters() -> Dictionary:
	var m := _json("res://data/monsters.json")
	return m.get("monsters", m)


func _monster_for(persona: String) -> String:
	var mons := _monsters()
	for mid in mons:
		if mons[mid] is Dictionary and str(mons[mid].get("boss_llm_persona_id", "")) == persona:
			return str(mid)
	return persona if mons.has(persona) else ""


## A boss built as the spawner builds it, as in test_a_boss_intent_changes_what_it_does.
func _boss(persona: String) -> Combatant:
	var mid := _monster_for(persona)
	var v: Dictionary = _monsters().get(mid, {})
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = persona
	c.max_hp = int(st.get("max_hp", 1000)); c.current_hp = c.max_hp
	c.max_mp = 99999; c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.magic_defense = int(st.get("magic_defense", 10))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.set_meta("llm_persona_id", persona)
	c.set_meta("boss_dialogue_phase", 99)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c


func _kit(boss: Combatant) -> Array:
	return (boss.job["abilities"] as Array).map(func(id): return JobSystem.get_ability(id))


func _party() -> Array:
	var out: Array = []
	for j in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var c := Combatant.new()
		autofree(c)
		c.combatant_name = j
		c.max_hp = 50000; c.current_hp = 50000
		c.job = {"id": j, "abilities": []}
		out.append(c)
	return out


## TURNS real caster decisions with `intent` held, seeded; returns the picked ability ids ("" for a plain attack).
func _turns(persona: String, intent: String, n: int = TURNS) -> Array:
	var boss := _boss(persona)
	if intent != "":
		boss.set_meta("llm_intent", intent)
	var kit := _kit(boss)
	var foes := _party()
	seed(SEED)
	var out: Array = []
	for _i in n:
		boss.current_mp = boss.max_mp
		out.append(str(_bm._ai_caster(boss, kit, foes).get("ability_id", "")))
	return out


func _magic_ids(persona: String) -> Array:
	return _kit(_boss(persona)).filter(func(a): return str(a.get("type", "")) == "magic").map(func(a): return str(a.get("id", "")))


func test_umbraxis_reaches_the_caster_ladder() -> void:
	var boss := _boss("umbraxis")
	assert_eq(_bm._get_ai_archetype(boss, _kit(boss)), "caster", "CONTROL: with his own kit Umbraxis is a caster, or these arms measure another ladder")


func test_with_null_field_held_most_of_his_spells_are_the_ones_it_names() -> void:
	var magic := _magic_ids("umbraxis")
	var spells: Array = _turns("umbraxis", "null_field").filter(func(id): return magic.has(id))
	assert_gt(spells.size(), TURNS / 3, "CONTROL: he cast %d spells in %d turns, too few to judge" % [spells.size(), TURNS])
	var named: int = spells.filter(func(id): return NULL_FIELD_SET.has(id)).size()
	var share: float = float(named) / float(spells.size())
	var windows := 0
	var majority := 0
	for i in range(spells.size() - 2):
		windows += 1
		var hits: int = [spells[i], spells[i + 1], spells[i + 2]].filter(func(id): return NULL_FIELD_SET.has(id)).size()
		if hits >= 2:
			majority += 1
	var window_share: float = float(majority) / float(windows)
	gut.p("  null_field held: %.3f of %d spells are Null Field/Shadow Bind; %.3f of 3-spell windows have >= 2" % [share, spells.size(), window_share])
	assert_gt(share, 0.5, "with Null Field announced, most of his spells must be the ones it names (%.3f)" % share)
	assert_gt(window_share, 0.5, "and most runs of his next 3 spells must mostly match it (%.3f)" % window_share)


func test_announcing_null_field_never_means_fewer_null_fields() -> void:
	var held: float = _turns("umbraxis", "null_field").count("null_field") / float(TURNS)
	var none: float = _turns("umbraxis", "").count("null_field") / float(TURNS)
	gut.p("  Null Field per turn: %.3f announced vs %.3f with no intent" % [held, none])
	assert_gt(held, none, "announcing Null Field must not lower how often he casts it (%.3f vs %.3f)" % [held, none])


func test_a_posture_that_names_a_spell_does_not_cut_his_casting() -> void:
	var magic := _magic_ids("umbraxis")
	var none: float = _turns("umbraxis", "").filter(func(id): return magic.has(id)).size() / float(TURNS)
	var held: float = _turns("umbraxis", "null_field").filter(func(id): return magic.has(id)).size() / float(TURNS)
	assert_gt(held, none - 0.03, "Null Field names a spell, so turtle's 0.6 must not cut his casting (%.3f vs %.3f with no intent)" % [held, none])


func test_control_a_posture_naming_no_spell_keeps_its_cast_cut() -> void:
	var magic := _magic_ids("umbraxis")
	var none: float = _turns("umbraxis", "").filter(func(id): return magic.has(id)).size() / float(TURNS)
	var dread: float = _turns("umbraxis", "existential_dread").filter(func(id): return magic.has(id)).size() / float(TURNS)
	assert_lt(dread, none - 0.03, "CONTROL: existential_dread names no spell, so its 0.9 cast weight still applies (%.3f vs %.3f)" % [dread, none])


func test_control_an_aggressive_posture_keeps_its_boost() -> void:
	var magic := _magic_ids("umbraxis")
	var none: float = _turns("umbraxis", "").filter(func(id): return magic.has(id)).size() / float(TURNS)
	var strike: float = _turns("umbraxis", "null_strike").filter(func(id): return magic.has(id)).size() / float(TURNS)
	assert_gt(strike, none + 0.1, "CONTROL: null_strike keeps aggress's 1.4 cast weight, not the 1.0 floor (%.3f vs %.3f)" % [strike, none])


## Every boss on the caster ladder, derived from boss_dialogue.json: its seeded picks are the same with and without the
## bias lookup reaching it unless one of its intents favours a spell in its kit. Umbraxis is the CONTROL that it can differ.
func test_only_a_caster_whose_intent_names_a_spell_changes_its_picks() -> void:
	var dialogue := _json("res://data/boss_dialogue.json")
	var casters: Array[String] = []
	var moved: Array[String] = []
	for persona in dialogue:
		if not (dialogue[persona] is Dictionary) or _monster_for(str(persona)) == "":
			continue
		var boss := _boss(str(persona))
		if _bm._get_ai_archetype(boss, _kit(boss)) != "caster":
			continue
		casters.append(str(persona))
		for it in (dialogue[persona] as Dictionary).get("scripted_intents", []):
			var intent := str((it as Dictionary).get("id", ""))
			var seen := _turns(str(persona), intent, 300)
			var blind := _boss(str(persona))
			blind.set_meta("llm_intent", intent)
			blind.set_meta("llm_persona_id", "__no_persona__")
			var kit := _kit(blind)
			var foes := _party()
			seed(SEED)
			var unbiased: Array = []
			for _i in 300:
				blind.current_mp = blind.max_mp
				unbiased.append(str(_bm._ai_caster(blind, kit, foes).get("ability_id", "")))
			if seen != unbiased:
				moved.append("%s/%s" % [persona, intent])
	gut.p("  caster-ladder bosses: %s; picks moved by a bias: %s" % [", ".join(casters), ", ".join(moved)])
	assert_true(casters.has("umbraxis"), "CONTROL: the derivation finds Umbraxis on the caster ladder")
	assert_true(moved.has("umbraxis/null_field"), "CONTROL: the probe sees a bias move picks, or it cannot see one either way")
	var others: Array = moved.filter(func(m): return not str(m).begins_with("umbraxis/"))
	assert_eq(others, [], "a caster boss whose intents name no spell changed its picks: %s" % str(others))
