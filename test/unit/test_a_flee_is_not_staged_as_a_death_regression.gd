extends GutTest

## struktured 2026-09-24: "if u flee it looks like a death sequence". The Rogue's Flee (and Smoke
## Bomb) end the battle through end_battle(false), the same call a party wipe makes. GameLoop already
## routes a loss with anyone standing back to the map, but BattleScene played the whole wipe first:
## "=== DEFEAT ===", a restart prompt, every PC's defeat animation, and the game-over music. BattleScene
## now asks the same question GameLoop does, whether anyone is still standing, and stages an escape.

const SceneScript = preload("res://src/battle/BattleScene.gd")


func _pc(alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.is_alive = alive
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	return c


func _scene_with(members: Array) -> Node:
	var scene = autofree(SceneScript.new())
	var typed: Array[Combatant] = []
	for m in members:
		typed.append(m)
	scene.party_members.assign(typed)
	return scene


func test_a_flee_with_the_party_standing_is_an_escape() -> void:
	assert_true(_scene_with([_pc(true), _pc(false)])._lost_battle_is_escape(),
		"a lost battle with a PC still standing was staged as a wipe (defeat poses, game-over music)")


func test_control_a_true_wipe_is_still_a_defeat() -> void:
	assert_false(_scene_with([_pc(false), _pc(false)])._lost_battle_is_escape(),
		"CONTROL: when nobody is standing it is a defeat, and the game-over flow must still play")
	assert_false(_scene_with([])._lost_battle_is_escape(), "CONTROL: an empty party is not an escape")


func test_the_escape_branch_stages_no_death() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var fn := src.find("func _on_battle_ended(")
	assert_gt(fn, -1, "_on_battle_ended must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var esc := body.find("elif _lost_battle_is_escape():")
	var defeat := body.find("=== DEFEAT ===")
	assert_gt(esc, -1, "_on_battle_ended must check for an escape")
	assert_gt(defeat, esc, "the escape check must come before the defeat branch")
	var branch := body.substr(esc, defeat - esc)
	assert_false(branch.contains("game_over"), "an escape must not play the game-over music")
	assert_false(branch.contains("play_defeat"), "an escape must not play the party's defeat animations")


func test_gameloop_routes_by_the_same_rule() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("_escape_survivors"), "GameLoop must still return a loss with survivors to the map")
