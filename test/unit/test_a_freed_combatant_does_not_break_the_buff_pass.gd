extends GutTest

## .654 gave dungeon bosses their intro speech, so a BattleScene can now sit on a dialogue while BattleManager still holds
## the PREVIOUS battle's parties. Its per-frame buff pass ran `combatant is Combatant` on those freed enemies: 15,099
## script errors in one render smoke, each one aborting the pass. Validity is checked first now.

const BattleScene := preload("res://src/battle/BattleScene.gd")
const SCENE_PATH := "res://src/battle/BattleScene.gd"

var _saved_players: Array[Combatant] = []
var _saved_enemies: Array[Combatant] = []
var _scene = null


func before_each() -> void:
	_saved_players = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_scene = BattleScene.new()


func after_each() -> void:
	BattleManager.player_party = _saved_players
	BattleManager.enemy_party = _saved_enemies
	_scene.free()


func test_the_buff_pass_survives_a_freed_enemy_and_still_reaches_the_living() -> void:
	var dead := Combatant.new()
	var alive: Combatant = autofree(Combatant.new())
	alive.is_alive = true
	var players: Array[Combatant] = []
	var enemies: Array[Combatant] = [dead, alive]
	BattleManager.player_party = players
	BattleManager.enemy_party = enemies
	dead.free()
	assert_false(is_instance_valid(BattleManager.enemy_party[0]), "CONTROL: the manager really holds a freed enemy")
	_scene._buff_visual_nodes[alive] = {}
	_scene._update_buff_debuff_visuals(0.0)
	assert_false(_scene._buff_visual_nodes.has(alive), "the pass got PAST the freed enemy and tidied the living one behind it")


func test_the_pass_checks_validity_before_the_type() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	var at := src.find("func _update_buff_debuff_visuals(")
	var next := src.find("\nfunc ", at + 1)
	var body := src.substr(at) if next < 0 else src.substr(at, next - at)
	assert_gt(at, -1, "CONTROL: the buff pass exists")
	var valid := body.find("is_instance_valid(combatant)")
	var typed := body.find("combatant is Combatant")
	assert_gt(valid, -1, "the pass asks whether the combatant is still alive in memory")
	assert_gt(typed, valid, "and asks it BEFORE `is`, which errors on a freed instance")
