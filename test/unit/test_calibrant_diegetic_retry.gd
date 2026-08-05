extends GutTest

## Fable's delivered design: the Calibrant's defeat lines "don't gloat — it files your death
## as its own calibration error and waits (diegetic retry)". The machinery: a wipe against a
## boss authored with diegetic_retry skips the GameOverScreen, speaks a player_wiped line,
## restores the party exactly as the retry arm does, and restarts the fight.
##
## The full await path (overlay -> restart) is scene-bound; what this drives is the DECISION
## function and the data contract, plus a source pin that the wipe branch actually consults
## the hook BEFORE _show_game_over_screen — the wiring half a decision test can't see.

const GameLoopScript = preload("res://src/GameLoop.gd")


func test_the_calibrant_authors_the_retry_contract() -> void:
	var f := FileAccess.get_file_as_string("res://data/monsters.json")
	var m: Dictionary = JSON.parse_string(f)
	var c: Dictionary = m.get("the_calibrant", {})
	assert_true(bool(c.get("diegetic_retry", false)),
		"the final boss refuses the game over — that is Fable's design, shipped as data")
	var wiped: Array = c.get("dialogue", {}).get("player_wiped", [])
	assert_gt(wiped.size(), 1, "multiple player_wiped lines so repeat deaths rotate, not repeat")
	assert_false(c.get("dialogue", {}).has("victory"),
		"no 'victory' key — nothing reads it; its lines live under 'defeat' (the boss's death "
		+ "speech, shown on player victory), the inversion this arc fixed")


func test_decision_finds_the_retry_boss_and_only_it() -> void:
	var gl = GameLoopScript.new()
	# NOT added to tree — _diegetic_retry_boss touches only EncounterSystem + its own field.
	gl._last_battle_enemies = ["slime", "the_calibrant"]
	var boss: Dictionary = gl._diegetic_retry_boss()
	assert_false(boss.is_empty(), "a party wipe against the Calibrant is refused")
	assert_eq(str(boss.get("id", "")), "the_calibrant", "and it names the right boss")
	assert_gt((boss.get("lines", []) as Array).size(), 0, "with lines to speak over the dark beat")

	gl._last_battle_enemies = ["slime", "goblin"]
	assert_true(gl._diegetic_retry_boss().is_empty(),
		"CONTROL: an ordinary wipe still reaches the GameOverScreen — retry is authored per boss")

	gl._last_battle_enemies = []
	assert_true(gl._diegetic_retry_boss().is_empty(), "CONTROL: no last battle, no retry")
	gl.free()


func test_the_wipe_branch_consults_the_hook_before_game_over() -> void:
	# The wiring half: a decision function nobody calls is the authored-no-consumer class.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var hook: int = src.find("if await _maybe_diegetic_retry():")
	var screen: int = src.find("await _show_game_over_screen()")
	assert_gt(hook, -1, "the wipe branch must consult the diegetic hook")
	assert_gt(screen, -1, "the game-over call must still exist for ordinary wipes")
	assert_lt(hook, screen,
		"and the hook runs FIRST — after the screen it would never fire")
	var ret: int = src.find("return", hook)
	assert_true(ret > hook and ret < hook + 120,
		"a successful retry must RETURN, or the GameOverScreen stacks on top of the retried fight")
