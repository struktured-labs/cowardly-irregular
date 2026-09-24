extends GutTest

## low_hp and defeat lines share dialogue_finished with the pre-battle intro.
## _on_dialogue_finished always called start_battle. Clicking through a wounded
## boss's line restarted the fight: the round snapped back to 1, Protect and
## banked AP were wiped, and selection opened again. The defeat line does the
## same after cleanup has already set INACTIVE, so the result screen grows a
## new PLAYER_SELECTING battle and a fresh died listener. Three finishes in a
## row are the repeated case. Only the intro sets _waiting_for_dialogue.

const SCENE := "res://src/battle/BattleScene.gd"

var _state = null
var _watched: Array = []


func before_each() -> void:
	_state = load("res://test/unit/helpers/battle_state.gd").new()
	_state.snapshot()
	_watched.clear()


func after_each() -> void:
	for c in _watched:
		if is_instance_valid(c):
			_drop_listeners(c)
	if _state:
		_state.restore()


func _fighter(who: String, spd: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.max_hp = 200
	c.current_hp = 200
	c.is_alive = true
	c.speed = spd
	c.attack = 20
	c.defense = 20
	add_child_autofree(c)
	_watched.append(c)
	return c


func _scene_for(party: Array[Combatant], foes: Array[Combatant]) -> Node:
	var scene = load(SCENE).new()
	autofree(scene)
	scene.party_members = party
	scene.test_enemies = foes
	return scene


func _drop_listeners(c: Combatant) -> void:
	for conn in c.died.get_connections():
		c.died.disconnect(conn["callable"])
	for conn in c.doom_ticked.get_connections():
		c.doom_ticked.disconnect(conn["callable"])
	for conn in c.status_tick_damage.get_connections():
		c.status_tick_damage.disconnect(conn["callable"])


func _has_protect(c: Combatant) -> bool:
	for entry in c.active_buffs:
		if str(entry.get("effect", "")) == "protect":
			return true
	return false


func test_mid_fight_lines_do_not_restart_the_battle() -> void:
	var hero := _fighter("Hero", 40)
	var foe := _fighter("Rat King", 10)
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [foe]
	BattleManager.start_battle(party, foes)
	BattleManager.current_round = 4
	hero.current_ap = 3
	hero.add_buff("protect", "defense", 1.5, 5)
	var before := hero.died.get_connections().size()
	var scene := _scene_for(party, foes)
	for _i in 3:
		scene._waiting_for_dialogue = false
		scene._on_dialogue_finished()
	assert_eq(hero.died.get_connections().size(), before,
		"three low-hp finishes left %d died listener(s); the live fight had %d" % [hero.died.get_connections().size(), before])
	assert_eq(BattleManager.current_round, 4,
		"clicking through the wounded line restarted the round counter")
	assert_eq(hero.current_ap, 3,
		"clicking through the wounded line wiped the AP the player had banked")
	assert_true(_has_protect(hero),
		"clicking through the wounded line cleared Protect")


func test_defeat_line_does_not_start_another_battle() -> void:
	var hero := _fighter("Hero", 40)
	var foe := _fighter("Rat King", 10)
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [foe]
	BattleManager.start_battle(party, foes)
	BattleManager.end_battle(false)
	var scene := _scene_for(party, foes)
	for _i in 3:
		scene._waiting_for_dialogue = false
		scene._on_dialogue_finished()
	assert_eq(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"finishing the boss's last words started another battle on top of the result")
	assert_eq(hero.died.get_connections().size(), 0,
		"the defeat line reconnected died %d time(s) after cleanup had already dropped it" % hero.died.get_connections().size())


func test_intro_still_starts_the_battle() -> void:
	if BattleManager.current_state != BattleManager.BattleState.INACTIVE and BattleManager.has_method("_cleanup_battle"):
		BattleManager._cleanup_battle()
	var hero := _fighter("Hero", 40)
	var foe := _fighter("Rat King", 10)
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [foe]
	var scene := _scene_for(party, foes)
	scene._waiting_for_dialogue = true
	scene._on_dialogue_finished()
	assert_false(scene._waiting_for_dialogue, "the intro latch must clear once the line is done")
	assert_ne(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"the pre-battle intro is the one finish that must still call start_battle")
	assert_eq(hero.died.get_connections().size(), 1,
		"the intro must connect died once, not stack it")
