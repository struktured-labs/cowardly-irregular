extends GutTest

## Smoke-race find 2026-07-03: start_solo_battle during an ACTIVE battle
## tore down the live battle's combatants while BattleManager still held
## them — "previously freed instance" errors every frame plus a duplicate
## battle_ended connection. Surfaced when the smoke's fixed post-battle
## sleep raced an RNG-long goblin fight; a stray cutscene battle step
## could do the same in production. Entry now refuses with "unavailable"
## (the sentinel CutsceneDirector's retry loop already aborts on).


func test_refuses_while_battle_active() -> void:
	# bare instance, never added to the tree: the guard is the first
	# statement and needs only the BattleManager autoload.
	var game_loop = load("res://src/GameLoop.gd").new()
	autofree(game_loop)
	var prev_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.SELECTION_PHASE
	var result: String = game_loop.start_solo_battle("fighter", "fighter_skeleton_knight")
	BattleManager.current_state = prev_state
	assert_eq(result, "unavailable",
		"an active battle must refuse solo entry — proceeding frees live combatants under BattleManager")


func test_guard_precedes_party_scan() -> void:
	# Both the guard and the missing-PC branch return "unavailable"; only
	# source order proves the guard (not an empty party) produced it.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn: int = src.find("func start_solo_battle")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, 900)
	var guard: int = body.find("BattleManager.current_state != BattleManager.BattleState.INACTIVE")
	var scan: int = body.find("for m in party")
	assert_gt(guard, -1, "active-battle guard must exist in start_solo_battle")
	assert_true(guard < scan, "guard must run before the party scan or an active battle still gets torn down")
