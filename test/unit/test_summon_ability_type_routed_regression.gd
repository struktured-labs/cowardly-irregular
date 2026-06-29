extends GutTest

## tick 392: Summoner's eidolon abilities (type=summon) now route to
## the magic execution path.
##
## Pre-fix: the player ability dispatch (BattleManager._execute_ability,
## match ability_type) had no "summon" arm. The Summoner job's 4
## eidolon abilities (summon_ifrit, summon_shiva, summon_ramuh,
## summon_bahamut) all author type=summon — every cast fell to `_:`
## push_warning, burning 30 MP for nothing.
##
## Post-fix routes "summon" → _execute_magic_ability. The eidolons
## have the magic-ability shape (damage_multiplier + element +
## target_type=all_enemies) so they fit cleanly. The ally-spawning
## summons (rat_swarm, pack_call) aren't in any player job, so this
## route doesn't break enemy-only paths.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_summon_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_ability(caster: Combatant, ability_id: String")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Must include "summon": match arm.
	assert_true(body.contains("\"summon\":"),
		"_execute_ability match must have a \"summon\" arm")
	# And it routes to magic execution.
	assert_true(body.contains("_execute_magic_ability(caster, ability, retargeted)"),
		"summon arm must call _execute_magic_ability")


func test_summoner_job_has_eidolons() -> void:
	# Sanity: ensure the Summoner job still authors the eidolon
	# abilities that the fix targets.
	var raw: String = FileAccess.get_file_as_string("res://data/jobs.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("summoner"))
	var sum_abilities: Array = data["summoner"].get("abilities", [])
	for eidolon in ["summon_ifrit", "summon_shiva", "summon_ramuh", "summon_bahamut"]:
		assert_true(eidolon in sum_abilities,
			"Summoner job must still include %s in its abilities list" % eidolon)


func test_eidolons_still_type_summon() -> void:
	# Sanity: the eidolons must still author type=summon. If a future
	# rebalance retypes them, the routing fix may need updating.
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	for eidolon in ["summon_ifrit", "summon_shiva", "summon_ramuh", "summon_bahamut"]:
		assert_true(data.has(eidolon))
		assert_eq(str(data[eidolon].get("type", "")), "summon",
			"%s must still author type=summon" % eidolon)
		# Must still have the magic-ability shape (damage_multiplier + element + all_enemies).
		assert_true(data[eidolon].has("damage_multiplier"),
			"%s must still author damage_multiplier" % eidolon)
		# Bahamut's Mega Flare is non-elemental — element is intentionally
		# absent. The magic execution path defaults to "" gracefully.
		assert_eq(str(data[eidolon].get("target_type", "")), "all_enemies",
			"%s must still author target_type=all_enemies" % eidolon)
