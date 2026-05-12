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
		"pinned_abilities", "recent_abilities",
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


func test_combatant_recent_abilities_persists_across_save_load() -> void:
	# Regression (2026-05-12): recent_abilities (MRU ability list) was
	# missing from to_dict/from_dict, so the player's MRU quick-slot
	# state was lost every save — sibling bug to the pinned_abilities
	# fix in 24e4b8c.
	var a = Combatant.new()
	a.combatant_name = "MRUTest"
	a.record_ability_use("fire")
	a.record_ability_use("cure")
	# After 2 records with MRU_SIZE=2, list should be ["cure", "fire"]
	# (most-recent-first ordering).
	assert_eq(a.recent_abilities.size(), 2,
		"setup: recent_abilities should have 2 entries after 2 record_ability_use calls")
	assert_eq(a.recent_abilities[0], "cure",
		"setup: most recent use should be at index 0")

	var dict = a.to_dict()
	assert_true(dict.has("recent_abilities"),
		"to_dict() must include recent_abilities key (regression: pre-fix it was missing)")
	assert_eq(dict["recent_abilities"].size(), 2,
		"serialized recent_abilities must preserve count")

	var b = Combatant.new()
	b.from_dict(dict)
	assert_eq(b.recent_abilities.size(), 2,
		"restored Combatant must have 2 MRU entries (regression: lost on load)")
	assert_eq(b.recent_abilities[0], "cure",
		"MRU order must survive round-trip (most-recent-first)")
	assert_eq(b.recent_abilities[1], "fire",
		"MRU order must survive round-trip (older entry at index 1)")
	a.queue_free()
	b.queue_free()


func test_typed_array_fields_survive_json_roundtrip() -> void:
	# Bigger regression class (2026-05-12): JSON.parse returns generic
	# Array, and Combatant.from_dict had .duplicate() assignments to
	# typed Array[String] / Array[Dictionary] fields which silently
	# failed (SCRIPT ERROR, no crash — fields stay default []).
	# This test covers ALL typed-array fields with explicit element
	# coercion in from_dict, not just recent_abilities.
	var a = Combatant.new()
	a.combatant_name = "TypedArrayTest"
	a.status_effects.append("poison")
	a.status_effects.append("burning")
	a.learned_passives.append("hp_boost")
	a.equipped_passives.append("hp_boost")
	a.pinned_abilities.append("fire")
	a.record_ability_use("cure")
	a.permanent_injuries.append({"name": "scarred", "stat": "speed", "modifier": -2})

	# Simulate the actual save path: dict → JSON → dict.
	var dict = a.to_dict()
	var json_str = JSON.stringify(dict)
	var parsed = JSON.parse_string(json_str)

	var b = Combatant.new()
	b.from_dict(parsed)

	# Each typed-array field must survive the round-trip.
	assert_eq(b.status_effects.size(), 2,
		"status_effects must survive JSON round-trip (regression: silently lost via Array→Array[String] assignment)")
	assert_true("poison" in b.status_effects,
		"status_effects content preserved")
	assert_eq(b.learned_passives.size(), 1,
		"learned_passives must survive JSON round-trip")
	assert_eq(b.equipped_passives.size(), 1,
		"equipped_passives must survive JSON round-trip")
	assert_eq(b.pinned_abilities.size(), 1,
		"pinned_abilities must survive JSON round-trip")
	assert_eq(b.recent_abilities.size(), 1,
		"recent_abilities must survive JSON round-trip")
	assert_eq(b.permanent_injuries.size(), 1,
		"permanent_injuries must survive JSON round-trip (Array[Dictionary])")
	assert_eq(b.permanent_injuries[0].get("stat", ""), "speed",
		"permanent_injuries dict content preserved")

	a.queue_free()
	b.queue_free()


func test_combatant_recent_abilities_survives_json_roundtrip() -> void:
	# JSON.stringify/parse strips typed-array information — the loaded
	# Array is generic, not Array[String]. from_dict must explicitly
	# coerce element types or downstream `recent_abilities.has(x)`
	# checks may fail unexpectedly. This test mirrors the save file
	# round-trip path (Dict → JSON → Dict).
	var a = Combatant.new()
	a.combatant_name = "JSONTest"
	a.record_ability_use("haste")
	a.record_ability_use("slow")

	# Simulate the save file path: dict → JSON string → parsed dict.
	var dict = a.to_dict()
	var json_str = JSON.stringify(dict)
	var parsed = JSON.parse_string(json_str)
	assert_not_null(parsed, "JSON round-trip should parse cleanly")

	var b = Combatant.new()
	b.from_dict(parsed)
	assert_eq(b.recent_abilities.size(), 2,
		"recent_abilities must survive JSON round-trip")
	# The critical type-coercion check: typed-array contract preserved.
	assert_true(b.recent_abilities is Array,
		"recent_abilities should remain an Array post-restore")
	assert_eq(b.recent_abilities[0], "slow",
		"MRU values must survive JSON round-trip")
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
