extends GutTest

## Temporal Shield (meta_auto_rewind_pending) rewound GameState and then
## returned from _on_battle_ended. The battle scene stays up, managed by
## GameLoop, so the defeat prompt does nothing, and the live party is still
## dead with the potions spent in the fight. The snapshot's HP, items, gold,
## and quest state never reach the characters the player is looking at.

const GameLoopScript := preload("res://src/GameLoop.gd")

## _ready would boot the title. The two overrides stop a missed shield from
## hanging on the real game-over wait, and stop a successful one from building a map.
class ShieldLoop extends GameLoopScript:
	var left_the_battle: bool = false
	var showed_game_over: bool = false

	func _ready() -> void:
		pass

	func _return_to_exploration(_force_battle_teardown: bool = false) -> void:
		left_the_battle = true
		current_state = LoopState.EXPLORATION

	func _show_game_over_screen() -> void:
		showed_game_over = true


var _backup: Dictionary = {}
var _history_backup: Array[Dictionary] = []


func before_each() -> void:
	_backup = GameState._create_save_data()
	_history_backup.clear()
	for entry in GameState.save_history:
		if entry is Dictionary:
			_history_backup.append(entry.duplicate(true))


func after_each() -> void:
	if _backup.is_empty():
		return
	GameState._apply_save_data(_backup)
	var restored: Array[Dictionary] = []
	for entry in _history_backup:
		restored.append(entry)
	GameState.save_history = restored
	_backup = {}


func _fighter() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Mira"
	JobSystem.assign_job(c, "fighter")
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	c.inventory = {"potion": 2}
	return c


func _arm_rewind(loop: ShieldLoop, member: Combatant) -> void:
	GameState.save_history.clear()
	GameState.meta_features["rewind_enabled"] = true
	GameState.llm_rebalance_enabled = false
	GameState.party_gold = 500
	GameState.quests = {"field_notes": {"state": "active", "objective_index": 0}}
	var typed: Array[Dictionary] = []
	typed.append(member.to_dict())
	GameState.player_party = typed
	# The checkpoint itself carries the shield, so a rewind that only
	# restores game_constants would re-arm the one-shot.
	GameState.game_constants["meta_auto_rewind_pending"] = true
	GameState.record_history_checkpoint(true)
	GameState.party_gold = 11
	GameState.quests = {"field_notes": {"state": "complete", "objective_index": 1}}
	GameState.record_history_checkpoint(true)
	loop.party.append(member)
	loop.add_child(member)
	# _ready fills HP/MP when the node enters the tree, so the wipe happens after that.
	member.inventory.clear()
	member.current_mp = 0
	member.die()
	loop.current_state = GameLoopScript.LoopState.BATTLE
	loop._spotlight_duel_active = false
	GameState.game_constants["meta_auto_rewind_pending"] = true


func test_shielded_wipe_restores_the_party_and_leaves_the_battle() -> void:
	var loop := ShieldLoop.new()
	add_child_autofree(loop)
	var member := _fighter()
	_arm_rewind(loop, member)
	await loop._on_battle_ended(false)
	assert_false(loop.showed_game_over,
		"an armed temporal shield must not show the game over screen")
	assert_true(loop.left_the_battle,
		"the rewind must leave the defeat screen — GameLoop owns it, so the restart prompt does nothing")
	assert_eq(loop.current_state, GameLoopScript.LoopState.EXPLORATION)
	assert_eq(loop.party.size(), 1)
	var back: Combatant = loop.party[0]
	assert_true(back.is_alive, "the rewound party is alive, not the wiped fight")
	assert_gt(back.current_hp, 0)
	assert_gt(back.current_mp, 0, "MP spent in the wiped fight comes back with the snapshot")
	assert_eq(int(back.inventory.get("potion", 0)), 2,
		"potions used in the wiped fight are in the snapshot and must be in hand again")
	assert_eq(GameState.party_gold, 500, "gold spent after the checkpoint comes back")
	assert_eq(str(GameState.quests.get("field_notes", {}).get("state", "")), "active",
		"a quest turned in during the wiped fight is active again")
	assert_false(bool(GameState.game_constants.get("meta_auto_rewind_pending", false)),
		"the shield is one shot — the snapshot must not re-arm it")


func test_an_unshielded_wipe_still_reaches_game_over() -> void:
	var loop := ShieldLoop.new()
	add_child_autofree(loop)
	var member := _fighter()
	_arm_rewind(loop, member)
	GameState.game_constants["meta_auto_rewind_pending"] = false
	await loop._on_battle_ended(false)
	assert_true(loop.showed_game_over, "without the shield a wipe still reaches game over")
	assert_false(loop.left_the_battle)
	assert_false(loop.party[0].is_alive)
	assert_eq(int(loop.party[0].inventory.get("potion", 0)), 0)
