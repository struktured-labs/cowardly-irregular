extends GutTest

## cowir-sfx msg 2165 (2026-07-04): monsters.json declared
## `signature_sfx` on 5 spotlight-duel minibosses but no src/ code
## read it. All 5 identity hits (bone rattle, pressure hit, ward-snap,
## prismatic shatter, courtly rebuff) sat on disk + in manifest and
## never played. Now fires once per battle per combatant at
## first-action, guarded by a _signature_fired meta flag.


func before_each() -> void:
	# Ensure the monster DB is loaded (EncounterSystem is an autoload).
	if EncounterSystem and EncounterSystem.monster_database.is_empty():
		EncounterSystem._load_monster_database()


func _boss_stub(monster_type: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Boss"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	c.set_meta("monster_type", monster_type)
	autofree(c)
	return c


func test_signature_fires_on_first_action_only() -> void:
	var bm = BattleManager
	var boss := _boss_stub("fighter_skeleton_knight")
	assert_false(boss.get_meta("_signature_fired", false),
		"clean stub must not have the fired flag pre-set")
	bm._maybe_play_signature_sfx(boss)
	assert_true(boss.get_meta("_signature_fired", false),
		"first call must mark the flag so subsequent actions don't re-fire")
	# Second call is a no-op — flag guards it. Idempotency = no double-fire.
	bm._maybe_play_signature_sfx(boss)
	assert_true(boss.get_meta("_signature_fired", false))


func test_no_meta_no_fire() -> void:
	var bm = BattleManager
	var mob := Combatant.new()
	mob.combatant_name = "Slime"
	autofree(mob)
	bm._maybe_play_signature_sfx(mob)
	assert_false(mob.get_meta("_signature_fired", false),
		"non-signature monsters must not mark the flag (no-op guard)")


func test_all_five_w1_spotlight_bosses_declare_signature_sfx() -> void:
	# Source pin: the roster (from monsters.json) is expected today.
	# If a spotlight boss LOSES its signature_sfx entry, this fails.
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for boss_id in ["fighter_skeleton_knight", "cleric_survive_target",
			"rogue_lockward", "mage_prismatic_construct", "bard_hostile_courtier"]:
		assert_true(m.has(boss_id), "spotlight boss %s missing from monsters.json" % boss_id)
		var sfx: String = str(m[boss_id].get("signature_sfx", ""))
		assert_ne(sfx, "",
			"%s must declare signature_sfx — cowir-sfx's authored identity hit" % boss_id)


func test_dispatch_calls_maybe_signature_before_action() -> void:
	# Source pin: the helper call sits BEFORE the match dispatch, so
	# the SFX fires as the boss's first action begins.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var maybe_idx: int = src.find("_maybe_play_signature_sfx(combatant)")
	var match_idx: int = src.find("match action.get(\"type\", \"\"):", maybe_idx)
	assert_gt(maybe_idx, -1, "_maybe_play_signature_sfx call must exist in dispatch")
	assert_gt(match_idx, -1, "action-type match must exist after the helper call")
	assert_lt(maybe_idx, match_idx,
		"helper must run BEFORE dispatch — otherwise the SFX plays after the action animation")
