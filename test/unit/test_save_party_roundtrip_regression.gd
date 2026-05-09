extends GutTest

## Regression tests for the catastrophic save bug where loading a save
## reset the live party to default level-1 starter characters.
##
## Bug history (2026-04-30, found via systematic save-system audit):
##   1. _sync_party_to_game_state synthesized a 5-field dict (name + job_id +
##      equipment IDs only). Missing: level, exp, HP/MP, abilities, passives,
##      inventory, status effects, secondary_job — *everything* that makes
##      a saved character mean anything.
##   2. _on_title_continue called _create_party() unconditionally, building
##      fresh defaults — and never read GameState.player_party.
##   3. The Game Over → Continue path likewise threw away saved data.
##
## Fix:
##   - Combatant.to_dict / from_dict expanded with level/exp, equipment,
##     secondary_job, learned/equipped passives, inventory, doom_counter.
##   - _sync_party_to_game_state now calls member.to_dict() (full state).
##   - GameLoop._restore_party_from_save_data() reconstructs live Combatants
##     from GameState.player_party, calling JobSystem.assign_job + EquipmentSystem
##     + PassiveSystem to reattach runtime hooks.
##   - _on_title_continue and _on_game_over_continue now call SaveSystem.load_game()
##     followed by _restore_party_from_save_data(); falling back to _create_party()
##     only if no save exists.


func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func test_combatant_to_dict_includes_full_state() -> void:
	# The serialization must include every field that affects gameplay.
	# Build a Combatant with non-default state and verify the dict has the keys.
	var c = Combatant.new()
	c.combatant_name = "TestHero"
	c.max_hp = 250
	c.current_hp = 100
	c.max_mp = 80
	c.current_mp = 25
	c.current_ap = 2
	c.attack = 30
	c.defense = 22
	c.magic = 15
	c.speed = 14
	c.job_level = 7
	c.job_exp = 350
	c.is_alive = true
	c.equipped_weapon = "iron_sword"
	c.equipped_armor = "leather_armor"
	c.equipped_accessory = "power_ring"
	c.secondary_job_id = "rogue"
	var la: Array[String] = ["slash", "guard"]
	c.learned_abilities = la
	var lp: Array[String] = ["weapon_mastery"]
	c.learned_passives = lp
	c.equipped_passives = lp.duplicate()
	c.inventory = {"potion": 5, "ether": 2}
	c.doom_counter = -1

	var d = c.to_dict()

	for key in ["name", "max_hp", "current_hp", "max_mp", "current_mp",
		"current_ap", "attack", "defense", "magic", "speed",
		"job_level", "job_exp", "is_alive",
		"equipped_weapon", "equipped_armor", "equipped_accessory",
		"secondary_job_id", "learned_abilities", "learned_passives",
		"equipped_passives", "inventory", "doom_counter",
		"pinned_abilities",
		"status_effects", "permanent_injuries", "job_profiles"]:
		assert_true(d.has(key),
			"Combatant.to_dict() must include '%s' (was missing pre-fix)" % key)

	# Spot-check values
	assert_eq(d["max_hp"], 250)
	assert_eq(d["job_level"], 7)
	assert_eq(d["equipped_weapon"], "iron_sword")
	assert_eq(d["secondary_job_id"], "rogue")
	c.queue_free()


func test_combatant_from_dict_round_trip_restores_state() -> void:
	# Round-trip: build A → to_dict → apply to B → assert B matches A on
	# the fields that matter for gameplay continuity.
	var a = Combatant.new()
	a.combatant_name = "Hero"
	a.max_hp = 175
	a.current_hp = 50
	a.max_mp = 60
	a.current_mp = 12
	a.current_ap = -1
	a.attack = 28
	a.defense = 18
	a.magic = 14
	a.speed = 16
	a.job_level = 5
	a.job_exp = 220
	a.equipped_weapon = "iron_sword"
	a.secondary_job_id = "rogue"
	var la2: Array[String] = ["slash"]
	a.learned_abilities = la2
	var ep2: Array[String] = ["hp_boost"]
	a.equipped_passives = ep2
	a.inventory = {"potion": 3}
	a.is_alive = true

	var dict = a.to_dict()

	var b = Combatant.new()
	b.from_dict(dict)

	assert_eq(b.combatant_name, "Hero")
	assert_eq(b.max_hp, 175)
	assert_eq(b.current_hp, 50)
	assert_eq(b.current_ap, -1)
	assert_eq(b.job_level, 5)
	assert_eq(b.job_exp, 220)
	assert_eq(b.equipped_weapon, "iron_sword")
	assert_eq(b.secondary_job_id, "rogue")
	assert_eq(b.learned_abilities.size(), 1)
	assert_eq(b.equipped_passives.size(), 1)
	assert_eq(b.inventory.get("potion", 0), 3)
	a.queue_free()
	b.queue_free()


func test_sync_party_uses_full_to_dict() -> void:
	# Source-level: confirm _sync_party_to_game_state calls to_dict()
	# instead of building a hand-rolled 5-field synth.
	var src = _read_file("res://src/GameLoop.gd")
	assert_string_contains(src, "member.to_dict()",
		"_sync_party_to_game_state must use Combatant.to_dict() so the " +
		"full character state survives save → load. Previously synthesized " +
		"a 5-field dict missing level/HP/MP/exp/abilities/passives/inventory.")


func test_restore_party_from_save_exists() -> void:
	# Source-level: the new restore function must exist and be wired.
	var src = _read_file("res://src/GameLoop.gd")
	assert_string_contains(src, "func _restore_party_from_save_data",
		"GameLoop must define _restore_party_from_save_data to rehydrate " +
		"runtime party from GameState.player_party — without this, " +
		"loading a save still resets the party to defaults.")
	assert_string_contains(src, "_restore_party_from_save_data()",
		"_restore_party_from_save_data must be called somewhere (Continue/" +
		"Game Over → Continue paths)")


func test_continue_loads_save_before_restoring() -> void:
	# Source-level: _on_title_continue must call SaveSystem.load_game and
	# _restore_party_from_save_data, with _create_party as a fallback path.
	var src = _read_file("res://src/GameLoop.gd")
	var idx = src.find("func _on_title_continue")
	assert_gt(idx, -1, "_on_title_continue must exist")
	# Slice the function body up to (but not including) the next func
	var rest = src.substr(idx)
	var next_func = rest.find("\nfunc ", 1)
	if next_func > 0:
		rest = rest.substr(0, next_func)
	# Required calls present
	assert_string_contains(rest, "SaveSystem.load_game(slot)",
		"Continue must call SaveSystem.load_game")
	assert_string_contains(rest, "_restore_party_from_save_data()",
		"Continue must call _restore_party_from_save_data")
	assert_string_contains(rest, "_create_party()",
		"Continue must keep _create_party fallback")
	# load_game must come before restore (look at first non-comment occurrence)
	# Easiest semi-robust check: load_game line appears before the
	# `if loaded and _restore_party_from_save_data():` line.
	var if_loaded_idx = rest.find("if loaded and _restore_party_from_save_data()")
	var load_idx = rest.find("loaded = SaveSystem.load_game(slot)")
	assert_gt(if_loaded_idx, -1,
		"Continue must guard restore with `if loaded and ...` so failed " +
		"loads fall back to _create_party")
	assert_gt(load_idx, -1, "Continue must assign loaded = SaveSystem.load_game(slot)")
	assert_lt(load_idx, if_loaded_idx,
		"load_game(slot) must execute before the if-loaded restore guard")


func test_game_over_continue_loads_save_before_restoring() -> void:
	# Same shape for the Game Over → Continue path.
	var src = _read_file("res://src/GameLoop.gd")
	# The pattern we expect after the "Load most recent save" comment in
	# the game-over continue branch: load_game, then _restore_party_from_save_data,
	# then fallback _create_party only on failure.
	var idx = src.find("Load most recent save and rehydrate")
	assert_gt(idx, -1,
		"Game Over → Continue must use the rehydrate path with a comment " +
		"explaining the bug fix. (Pre-fix the path did SaveSystem.load_game " +
		"followed by _create_party() unconditionally, ignoring the save.)")
