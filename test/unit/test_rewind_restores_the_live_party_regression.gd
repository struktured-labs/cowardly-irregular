extends GutTest

## Rewind applied the save dict and left the fight's Combatants alone, so HP, a spent
## potion, poison, a taunt, a buff, AP, and a once-per-battle flag stayed while gold
## snapped back. The next menu sync then overwrote the restored dict with the wounded
## party. The battle also kept going, so the enemy's missing HP was a free advantage
## the ability text does not offer. Checkpoints also embedded save_history, and
## applying one replaced the ring, so the point just restored could not be rewound to.

var _backup: Dictionary = {}
var _backup_boss: Dictionary = {}


func before_each() -> void:
	_backup = GameState.to_dict()
	_backup_boss = GameState.pending_boss_defeat.duplicate(true)


func after_each() -> void:
	if not _backup.is_empty():
		GameState._apply_save_data(_backup)
	GameState.pending_boss_defeat = _backup_boss.duplicate(true)
	_backup = {}
	_backup_boss = {}


func _person(who: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": who, "max_hp": hp, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func _manager() -> Node:
	var bm: Node = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	return bm


func test_taking_time_mage_unlocks_rewind() -> void:
	assert_false(bool(GameState.meta_features.get("rewind_enabled", true)),
		"rewind starts locked — assigning the job is what turns it on")
	var mage := _person("Lyra", 80)
	assert_true(JobSystem.assign_job(mage, "time_mage"))
	assert_true(bool(GameState.meta_features.get("rewind_enabled", false)),
		"a primary Time Mage must unlock rewind or the ability can never restore anything")
	GameState.meta_features["rewind_enabled"] = false
	var fighter := _person("Bram", 80)
	assert_true(JobSystem.assign_job(fighter, "fighter"))
	assert_false(bool(GameState.meta_features.get("rewind_enabled", true)),
		"a non-Time-Mage job must not unlock rewind")
	assert_true(JobSystem.assign_secondary_job(fighter, "time_mage"))
	assert_true(bool(GameState.meta_features.get("rewind_enabled", false)),
		"Time Mage as a secondary job lends Rewind, so it has to unlock the same gate")


func test_rewind_puts_the_wounded_party_back_and_leaves_the_fight() -> void:
	GameState.save_history.clear()
	GameState.unlock_time_mage_features()
	GameState.party_gold = 100
	GameState.game_constants["quest_c3_auto_streak"] = 2
	GameState.quests["world1_chapter_three"] = {"state": "active", "objective_index": 1}
	GameState.player_party.clear()
	GameState.player_party.append({"name": "Lyra", "current_hp": 999, "max_hp": 999, "inventory": {}})
	var lyra := _person("Lyra", 80)
	lyra.add_item("potion", 1)
	var goblin := _person("Goblin", 40)
	var bm := _manager()
	var players: Array[Combatant] = [lyra]
	var foes: Array[Combatant] = [goblin]
	bm.start_battle(players, foes)
	assert_eq(int(GameState.player_party[0].get("current_hp", -1)), 80,
		"the battle-start checkpoint must be the body that entered, not the stale menu row at 999")
	assert_eq(int(GameState.player_party[0].get("inventory", {}).get("potion", 0)), 1,
		"the opening snapshot has to include the potion she walked in with")
	lyra.current_hp = 20
	assert_true(lyra.remove_item("potion", 1))
	lyra.add_status("poison", 4)
	lyra.add_status("taunted_Goblin", 3)
	lyra.add_buff("Haste", "speed", 1.2, 3)
	lyra.current_ap = 3
	lyra.set_meta("_signature_fired", true)
	goblin.current_hp = 12
	GameState.party_gold = 9999
	GameState.game_constants["quest_c3_auto_streak"] = 0
	GameState.pending_boss_defeat = {"boss_id": "mordaine"}
	assert_true(GameState.record_history_checkpoint(true))
	assert_eq(GameState.save_history.size(), 2, "opening checkpoint plus the wounded present")
	bm._execute_meta_ability(lyra, {"id": "rewind", "meta_effect": "time_rewind"}, [])
	assert_eq(lyra.current_hp, 80, "rewind must put her HP back on the person in the fight")
	assert_eq(lyra.get_item_count("potion"), 1, "the potion she spent has to come back")
	assert_false(lyra.has_status("poison"), "poison applied after the snapshot must not stick")
	assert_false(lyra.has_status("taunted_Goblin"), "a taunt lock from this fight must not stick")
	assert_eq(lyra.active_buffs.size(), 0, "a buff gained this fight must not stick")
	assert_eq(lyra.current_ap, 0, "AP is part of the opening snapshot")
	assert_false(lyra.has_meta("_signature_fired"), "a once-per-battle flag must not survive the rewind")
	assert_eq(GameState.party_gold, 100, "gold returns with the same snapshot as her body")
	assert_eq(int(GameState.game_constants.get("quest_c3_auto_streak", -1)), 2,
		"leaving the fight must not zero the autobattle streak the snapshot restored")
	assert_eq(GameState.pending_boss_defeat.size(), 0,
		"a rewound boss fight must not leave a defeat IOU for the next victory to cash")
	assert_false(bm.is_battle_active(), "the fight has to end — the enemy's missing HP is not kept as progress")
	assert_eq(goblin.current_hp, 12, "the enemy is not healed or finished; the battle simply stops")
	assert_eq(GameState.save_history.size(), 1,
		"one rewind drops only the present checkpoint and keeps the one it restored")


func test_an_enemy_rewind_does_not_walk_the_player_out() -> void:
	GameState.save_history.clear()
	GameState.unlock_time_mage_features()
	GameState.party_gold = 40
	GameState.record_history_checkpoint(true)
	GameState.party_gold = 90
	GameState.record_history_checkpoint(true)
	var lyra := _person("Lyra", 80)
	lyra.current_hp = 15
	var phantom := _person("Time Phantom", 50)
	var bm := _manager()
	var side: Array[Combatant] = [lyra]
	var foes: Array[Combatant] = [phantom]
	bm.player_party = side
	bm.enemy_party = foes
	bm.current_state = load("res://src/battle/BattleManager.gd").BattleState.EXECUTION_PHASE
	bm._execute_meta_ability(phantom, {"id": "rewind_turn", "meta_effect": "rewind_turn"}, [])
	assert_eq(lyra.current_hp, 15, "an enemy rewind must not heal the party")
	assert_true(bm.is_battle_active(), "an enemy rewind must not end the player's fight")
