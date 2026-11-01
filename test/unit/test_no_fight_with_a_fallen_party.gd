extends GutTest

## struktured 2026-11-01 (.758): "after autogrinding I entered a battle with my entire party already KOed". A grind that ended
## in a wipe left him on the field at 0 HP, and the next roamer touch started a chain he lost instantly. Whatever path leaves a
## fallen party on the field, the overworld must not start a fight with it.


func _hero(alive: bool) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Hero"
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	c.is_alive = alive
	add_child_autofree(c)
	return c


func _loop(alive_flags: Array) -> Node:
	var gl = load("res://src/GameLoop.gd").new()
	autofree(gl)
	var p: Array[Combatant] = []
	for a in alive_flags:
		p.append(_hero(a))
	gl.party = p
	return gl


func test_a_party_with_anyone_standing_can_fight() -> void:
	assert_true(_loop([false, true, false])._party_can_fight(), "one member standing is enough to fight")
	assert_false(_loop([false, false, false])._party_can_fight(), "an all-KO party was judged able to fight")


func test_a_touch_never_starts_a_fight_with_an_all_ko_party() -> void:
	var gl := _loop([false, false, false, false, false])
	gl._on_exploration_battle_triggered(["slime", "slime", "slime"], "plains")
	assert_false(gl._battle_transition_starting, "an encounter began commencing against a fallen party")
	assert_eq(gl._chain_links.size(), 0, "a chain was planned against a fallen party")


func test_a_blocked_touch_leaves_the_joiners_where_they_stand() -> void:
	var scene_script := GDScript.new()
	scene_script.source_code = "extends Node2D\nvar monster_spawner: Node = null\n"
	scene_script.reload()
	var explore: Node2D = scene_script.new()
	autofree(explore)
	var sp := MonsterSpawner.new()
	autofree(sp)
	sp._chain_joiners = [["bat", "bat"]]
	sp._chain_frame = Engine.get_physics_frames()
	explore.monster_spawner = sp
	var gl := _loop([false, false])
	gl._exploration_scene = explore
	gl._on_exploration_battle_triggered(["slime"], "plains")
	assert_eq(sp._chain_joiners, [["bat", "bat"]], "a refused fight still consumed its chain's joiners")
