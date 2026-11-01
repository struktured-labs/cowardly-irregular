extends GutTest

## struktured 2026-10-31, chained encounters: alerted roamers near a touch join the fight -- one battle if they fit,
## else back-to-back, ONE VICTORY SCREEN PER LINK, rewards counted by GROUPS (+20%/group cap 2x, drops +10% cap 1.5x).

const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const RoamingMonsterScript := preload("res://src/exploration/RoamingMonster.gd")
const FOE := "chain_test_unlisted_foe"

var _guard: RefCounted = null
var _repel_before: int = 0


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_repel_before = int(EncounterSystem.repel_steps_remaining)
	EncounterSystem.repel_steps_remaining = 0


func after_each() -> void:
	EncounterSystem.repel_steps_remaining = _repel_before
	BattleManager.chain_groups = 1
	for key in ["defeated_monsters", "defeated_counts", "seen_monsters", "seen_monsters_last_location"]:
		var bucket: Variant = GameState.game_constants.get(key, null)
		if bucket is Dictionary:
			(bucket as Dictionary).erase(FOE)
	if _guard != null:
		_guard.restore()


func test_one_battle_holds_what_the_battle_scene_has_room_for() -> void:
	var tscn := FileAccess.get_file_as_string("res://src/battle/BattleScene.tscn")
	var slots := RegEx.create_from_string('name="Enemy\\d+Pos"').search_all(tscn).size()
	assert_gt(slots, 0, "CONTROL: BattleScene.tscn still names its enemy slots")
	assert_eq(MonsterSpawner.CHAIN_CAPACITY, slots, "a chain link holds a different number of enemies than a battle can stand up")


func test_groups_that_fit_share_one_battle() -> void:
	var links := MonsterSpawner.pack_chain([["slime"], ["bat", "bat"]])
	assert_eq(links, [[["slime"], ["bat", "bat"]]], "two groups totalling three did not share one battle")


func test_groups_that_do_not_fit_go_back_to_back_and_are_never_split() -> void:
	var links := MonsterSpawner.pack_chain([["slime", "slime"], ["bat", "bat"], ["imp"]])
	assert_eq(links.size(), 2, "expected two battles")
	assert_eq(links[0], [["slime", "slime"], ["imp"]], "battle one is not the leader's group plus what fits beside it")
	assert_eq(links[1], [["bat", "bat"]], "a group was split or lost")


func test_a_chain_stops_at_its_battle_cap() -> void:
	var groups: Array = []
	for i in range(MonsterSpawner.CHAIN_MAX_BATTLES + 2):
		groups.append(["wolf", "wolf", "wolf"])
	assert_eq(MonsterSpawner.pack_chain(groups).size(), MonsterSpawner.CHAIN_MAX_BATTLES, "a chain ran past its cap")


func test_the_reward_formula_counts_groups_and_caps() -> void:
	assert_almost_eq(BattleManager.chain_reward_factor(1), 1.0, 0.001, "a lone group earned a chain bonus")
	assert_almost_eq(BattleManager.chain_reward_factor(2), 1.2, 0.001)
	assert_almost_eq(BattleManager.chain_reward_factor(6), 2.0, 0.001)
	assert_almost_eq(BattleManager.chain_reward_factor(9), 2.0, 0.001, "EXP/gold passed its 2x cap")
	assert_almost_eq(BattleManager.chain_drop_factor(2), 1.1, 0.001)
	assert_almost_eq(BattleManager.chain_drop_factor(9), 1.5, 0.001, "drops passed their 1.5x cap")


func _roamer(id: String, pos: Vector2, mood: int, elite: bool = false) -> Node2D:
	var m = RoamingMonsterScript.new()
	m.monster_id = id
	m.monster_types = [id]
	m.elite = elite
	add_child_autofree(m)
	m.global_position = pos
	m._mood = mood
	return m


func test_alerted_and_angry_roamers_join_nearest_first() -> void:
	var M = RoamingMonsterScript.Mood
	var toucher := _roamer("slime", Vector2(0, 0), M.ANGRY)
	var far := _roamer("bat", Vector2(200, 0), M.ALERTED)
	var near := _roamer("goblin", Vector2(50, 0), M.ANGRY)
	var calm := _roamer("imp", Vector2(10, 0), M.CALM)
	var afraid := _roamer("imp", Vector2(12, 0), M.AFRAID)
	var elite := _roamer("wolf", Vector2(14, 0), M.ANGRY, true)
	var groups := MonsterSpawner.chain_joiners_for(toucher, [toucher, far, near, calm, afraid, elite])
	assert_eq(groups.size(), 2, "only the alerted and angry non-elites join: %s" % str(groups))
	assert_eq(str(groups[0][0]), "goblin", "the nearer joiner is not first")
	assert_eq(str(groups[1][0]), "bat")


func test_nothing_joins_under_repel_or_while_fading() -> void:
	var M = RoamingMonsterScript.Mood
	var toucher := _roamer("slime", Vector2(0, 0), M.ANGRY)
	var other := _roamer("bat", Vector2(40, 0), M.ANGRY)
	assert_eq(MonsterSpawner.chain_joiners_for(toucher, [other]).size(), 1, "CONTROL: an angry roamer joins")
	other._begin_fade()
	assert_eq(MonsterSpawner.chain_joiners_for(toucher, [other]).size(), 0, "a fading roamer joined")
	other._fading = false
	EncounterSystem.repel_steps_remaining = 5
	assert_eq(MonsterSpawner.chain_joiners_for(toucher, [other]).size(), 0, "a roamer joined under Repel")


func test_joiners_are_read_only_on_the_frame_of_their_touch() -> void:
	var sp := MonsterSpawner.new()
	autofree(sp)
	sp._chain_joiners = [["bat"]]
	sp._chain_frame = Engine.get_physics_frames()
	assert_eq(sp.take_chain_joiners(), [["bat"]], "CONTROL: same-frame joiners are handed over")
	assert_eq(sp.take_chain_joiners(), [], "joiners were handed over twice")
	sp._chain_joiners = [["bat"]]
	sp._chain_frame = Engine.get_physics_frames() - 1
	assert_eq(sp.take_chain_joiners(), [], "a blocked touch's joiners leaked into a later battle")


func _game_loop_with_joiners(joiners: Array) -> Node:
	var gl = load("res://src/GameLoop.gd").new()
	autofree(gl)
	var scene_script := GDScript.new()
	scene_script.source_code = "extends Node2D\nvar monster_spawner: Node = null\n"
	scene_script.reload()
	var explore: Node2D = scene_script.new()
	autofree(explore)
	var sp := MonsterSpawner.new()
	autofree(sp)
	sp._chain_joiners = joiners
	sp._chain_frame = Engine.get_physics_frames()
	explore.monster_spawner = sp
	gl._exploration_scene = explore
	return gl


func test_the_game_loop_fights_the_chain_link_by_link() -> void:
	var gl := _game_loop_with_joiners([["bat", "bat"], ["imp"]])
	var first: Array = gl._begin_chain(["slime", "slime"])
	assert_eq(first, ["slime", "slime", "imp"], "battle one is not the leader plus the joiner that fits")
	assert_eq(gl._chain_engaged, 2, "battle one engaged two groups")
	assert_eq(gl._chain_links.size(), 1, "the second battle was not queued")
	assert_eq(gl._next_chain_link(), ["bat", "bat"])
	assert_eq(gl._chain_engaged, 3, "groups engaged do not accumulate across the chain")
	gl._end_chain()
	assert_eq([gl._chain_links.size(), gl._chain_engaged], [0, 0], "an ended chain left state behind")


func test_a_touch_with_no_joiners_is_one_ordinary_battle() -> void:
	var gl := _game_loop_with_joiners([])
	assert_eq(gl._begin_chain(["slime"]), ["slime"])
	assert_eq([gl._chain_links.size(), gl._chain_engaged], [0, 0], "a lone touch started a chain")


func _exp_for(groups: int) -> Dictionary:
	var hero := Combatant.new()
	hero.combatant_name = "Fighter"
	hero.job_level = 1
	hero.job_exp = 0
	hero.is_alive = true
	add_child_autofree(hero)
	var foe := Combatant.new()
	foe.combatant_name = FOE
	foe.max_hp = 10
	foe.current_hp = 0
	foe.is_alive = false
	foe.set_meta("monster_type", FOE)
	add_child_autofree(foe)
	BattleManager._first_damage_phase = -1
	BattleManager._one_shot_achieved = false
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	BattleManager._ko_this_battle.clear()
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [foe]
	var everyone: Array[Combatant] = [hero, foe]
	BattleManager.player_party = party
	BattleManager.enemy_party = foes
	BattleManager.all_combatants = everyone
	BattleManager.defer_victory_payout = false
	BattleManager.chain_groups = groups
	BattleManager.end_battle(true)
	return BattleManager._battle_results.duplicate(true)


func test_a_victory_pays_the_chain_bonus_and_says_so() -> void:
	var lone := _exp_for(1)
	var chained := _exp_for(3)
	var base: int = int(lone["char_results"][0]["exp_gained"])
	assert_gt(base, 0, "CONTROL: the lone battle paid EXP")
	assert_eq(int(chained["char_results"][0]["exp_gained"]), int(lone["base_exp"] * 1.4), "three groups did not pay +40% EXP")
	var chain_bonus: Array = (chained["bonuses"] as Array).filter(func(b): return b.get("type", "") == "chain")
	assert_eq(chain_bonus.size(), 1, "the victory results do not name the chain bonus")
	assert_eq(int(chain_bonus[0].get("groups", 0)) if not chain_bonus.is_empty() else 0, 3)
	assert_eq(BattleManager.chain_groups, 1, "the chain count outlived its battle")
