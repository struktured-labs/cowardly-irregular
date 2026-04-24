extends GutTest

## Regression tests for commit 22bd71e — 4 battle bug fixes:
##   1. CTB turn-order overlapping PartyStatusPanel
##   2. Monster stuck in attack pose (tween interruption)
##   3. Last party KO sprite not graying (hp_changed/is_alive ordering)
##   4. Menu attack immunity (RoamingMonster.deactivate synchronous)
##
## Separated from test_battle_bugfix_regression.gd so it can be run in
## isolation via run_single_test.gd without hitting autoload compile errors
## in the larger file.

const Combatant = preload("res://src/battle/Combatant.gd")

var _combatant: Combatant


func before_each() -> void:
	_combatant = Combatant.new()
	_combatant.combatant_name = "Test"
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.max_mp = 50
	_combatant.current_mp = 50
	_combatant.attack = 20
	_combatant.defense = 10
	_combatant.magic = 15
	_combatant.speed = 12
	add_child_autofree(_combatant)


# ===========================================================================
# Bug #3: Last party KO sprite not graying (is_alive ordering)
# ===========================================================================
## The critical fix: hp_changed must fire AFTER is_alive is flipped to false
## so UI listeners (BattleUIManager._update_member_status) see the correct
## state and apply gray modulate on the lethal hit.

func test_is_alive_is_false_when_hp_changed_fires_on_lethal_hit() -> void:
	var observed_is_alive = [true]  # Wrong default — confirms signal fired

	_combatant.current_hp = 10
	_combatant.hp_changed.connect(func(_old, new_hp):
		if new_hp <= 0:
			observed_is_alive[0] = _combatant.is_alive
	)

	_combatant.take_damage(999)

	assert_false(observed_is_alive[0],
		"is_alive must be false when hp_changed fires on lethal hit (regression: last party KO not graying)")


func test_non_lethal_damage_keeps_is_alive_true_at_hp_changed() -> void:
	var observed_is_alive = [false]

	_combatant.current_hp = 100
	_combatant.hp_changed.connect(func(_old, _new):
		observed_is_alive[0] = _combatant.is_alive
	)

	_combatant.take_damage(30)

	assert_true(observed_is_alive[0],
		"is_alive should remain true when hp_changed fires on non-lethal damage")


func test_died_signal_still_fires_after_hp_changed_on_lethal_hit() -> void:
	# Regression: the reordering must not break the died signal emission.
	var hp_changed_count = [0]
	var died_count = [0]

	_combatant.current_hp = 10
	_combatant.hp_changed.connect(func(_old, _new): hp_changed_count[0] += 1)
	_combatant.died.connect(func(): died_count[0] += 1)

	_combatant.take_damage(999)

	assert_eq(hp_changed_count[0], 1, "hp_changed must fire exactly once on lethal hit")
	assert_eq(died_count[0], 1, "died must fire exactly once on lethal hit")


# ===========================================================================
# Bug #4: RoamingMonster.deactivate() — menu attack immunity
# ===========================================================================
## A queue_free()'d monster can still fire body_entered in the same physics
## frame. deactivate() must immediately neutralize the monster synchronously
## so no battle triggers leak into menus.
##
## These tests are structural (source-level) since RoamingMonster._ready()
## requires full physics-server setup which GUT test runs don't provide.

func test_roaming_monster_defines_deactivate() -> void:
	var file = FileAccess.open("res://src/exploration/RoamingMonster.gd", FileAccess.READ)
	assert_not_null(file, "RoamingMonster.gd should exist")
	var text = file.get_as_text()
	file.close()

	assert_true(text.find("func deactivate(") != -1,
		"RoamingMonster must define deactivate() (regression: menu attack immunity)")


func test_roaming_monster_deactivate_sets_active_false() -> void:
	var file = FileAccess.open("res://src/exploration/RoamingMonster.gd", FileAccess.READ)
	assert_not_null(file, "RoamingMonster.gd should exist")
	var text = file.get_as_text()
	file.close()

	# Locate deactivate body and verify key field mutations
	var idx = text.find("func deactivate(")
	assert_gt(idx, -1, "deactivate() must exist")
	var body_end = text.find("\n\n", idx)
	if body_end == -1:
		body_end = text.length()
	var body = text.substr(idx, body_end - idx)

	assert_true(body.find("_active = false") != -1,
		"deactivate() must set _active = false (body_entered gating)")
	assert_true(body.find("_fading = false") != -1,
		"deactivate() must set _fading = false (prevent fade re-entry)")
	assert_true(body.find("_collision") != -1 and body.find("disabled = true") != -1,
		"deactivate() must disable the CollisionShape2D synchronously")
	assert_true(body.find("_sprite") != -1 and body.find("visible = false") != -1,
		"deactivate() must hide the sprite (no visual ghost during fade)")


func test_monster_spawner_calls_deactivate_before_queue_free() -> void:
	# MonsterSpawner._despawn_all() must invoke deactivate() synchronously
	# before queue_free() — the whole point is to neutralize BEFORE the
	# deferred queue_free takes effect.
	var file = FileAccess.open("res://src/exploration/MonsterSpawner.gd", FileAccess.READ)
	assert_not_null(file, "MonsterSpawner.gd should exist")
	var text = file.get_as_text()
	file.close()

	assert_true(text.find(".deactivate()") != -1,
		"MonsterSpawner must call monster.deactivate() (regression: menu attack immunity)")
	# Verify deactivate precedes queue_free for the same monster context
	var deact_idx = text.find(".deactivate()")
	var qf_idx = text.find("queue_free()", deact_idx)
	assert_gt(qf_idx, deact_idx,
		"deactivate() must be called BEFORE queue_free() to neutralize the monster synchronously")


# ===========================================================================
# Bug #1: CTB timeline panel position (layout integrity)
# ===========================================================================
## Turn order overlapped the PartyStatusPanel. Fix: CTB panel anchors to
## PRESET_BOTTOM_RIGHT with offset_top <= -240; party panel bottom at 460.

func test_battle_scene_party_panel_offset_bottom_is_460() -> void:
	var file = FileAccess.open("res://src/battle/BattleScene.tscn", FileAccess.READ)
	assert_not_null(file, "BattleScene.tscn should exist")
	var text = file.get_as_text()
	file.close()

	# Before fix: offset_bottom=520 which overlapped CTB. Now should be 460.
	assert_true(text.find('offset_bottom = 460.0') != -1,
		"BattleScene.tscn PartyStatusPanel offset_bottom should be 460.0 (regression: CTB/party overlap)")


func test_battle_ui_manager_ctb_panel_bottom_right_anchor() -> void:
	var file = FileAccess.open("res://src/battle/BattleUIManager.gd", FileAccess.READ)
	assert_not_null(file, "BattleUIManager.gd should exist")
	var text = file.get_as_text()
	file.close()

	assert_true(text.find("PRESET_BOTTOM_RIGHT") != -1,
		"BattleUIManager must anchor CTB panel via PRESET_BOTTOM_RIGHT")
	# offset_top must be -240 (or more negative) to clear party panel gutter
	var has_240 = text.find("offset_top = -240") != -1 or text.find("offset_top = -241") != -1
	assert_true(has_240,
		"BattleUIManager CTB offset_top must be -240 or beyond (regression: CTB/party overlap)")


# ===========================================================================
# Bug #2: Monster stuck in attack pose (safety-net reset)
# ===========================================================================
## _reset_attacker_home() must exist, be invoked from the action-executed
## handler, and tolerate null/invalid combatants without crashing.

func test_battle_scene_defines_reset_attacker_home() -> void:
	var file = FileAccess.open("res://src/battle/BattleScene.gd", FileAccess.READ)
	assert_not_null(file, "BattleScene.gd should exist")
	var text = file.get_as_text()
	file.close()

	assert_true(text.find("func _reset_attacker_home(") != -1,
		"BattleScene must define _reset_attacker_home() (safety-net for stuck attack poses)")
	assert_true(text.find("_reset_attacker_home(combatant)") != -1,
		"BattleScene must CALL _reset_attacker_home(combatant) from action execution")


func test_reset_attacker_home_guards_against_null_combatant() -> void:
	# The method must early-return on null/invalid combatants — called from
	# _on_action_executed which may fire after cleanup.
	var file = FileAccess.open("res://src/battle/BattleScene.gd", FileAccess.READ)
	assert_not_null(file, "BattleScene.gd should exist")
	var text = file.get_as_text()
	file.close()

	# Find the function body and verify null guard at entry
	var idx = text.find("func _reset_attacker_home(")
	assert_gt(idx, -1, "_reset_attacker_home must exist")
	var body = text.substr(idx, 400)  # Read ~400 chars into function body
	assert_true(body.find("not combatant") != -1 or body.find("combatant == null") != -1,
		"_reset_attacker_home must guard against null combatant at entry")
	assert_true(body.find("is_instance_valid(combatant)") != -1,
		"_reset_attacker_home must guard against freed combatant via is_instance_valid")
