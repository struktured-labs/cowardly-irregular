extends GutTest

## Playtest 2026-07-12: Cleric spotlight victory RESTARTED in the background
## during the aftermath cutscene and boss battle music kept playing; Rogue
## spotlight aftermath dumped the player back to the overworld frozen.
##
## Root: GameLoop._on_battle_ended short-circuited for _spotlight_duel_active
## and returned WITHOUT tearing down the BattleScene (current_scene). The
## stale scene kept ticking → boss music persisted; some tick loop on the
## stale scene surfaced as the "background restart" (end_battle clears
## _win_condition first, so the exact mechanism isn't survive_turns
## re-evaluation — the fix root-cures either way by removing the stale
## scene); the aftermath narration overlaid a live battle and
## _unfreeze_player had no player behind the CutsceneDirector layer.
##
## Fix: after the await spotlight_battle_ended + party restore in
## start_solo_battle, on VICTORY call _return_to_exploration to swap the
## BattleScene out under the cutscene's opaque layer. On defeat the retry
## loop's next _start_battle_async frees the scene, so no teardown needed.


func test_start_solo_battle_tears_down_battle_scene_on_victory() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func start_solo_battle")
	assert_gt(i, -1)
	# Read the full function body — scan to the next top-level func.
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 4000)
	assert_true("await spotlight_battle_ended" in body,
		"start_solo_battle must await the battle-end signal (unchanged)")
	assert_true("if result:" in body and "_return_to_exploration()" in body,
		"on victory, start_solo_battle must return-to-exploration so the stale BattleScene is freed and area music replaces the battle theme")
	# _cutscene_cooldown must be set true before the exploration rebuild so
	# _start_exploration's pending-story-cutscene gate doesn't re-fire the
	# same spotlight cutscene → infinite loop.
	var vi: int = body.find("if result:")
	var vblock := body.substr(vi, 400)
	assert_true("_cutscene_cooldown = true" in vblock,
		"before _return_to_exploration under a live cutscene, set _cutscene_cooldown=true so the same spotlight cutscene isn't re-fired by _start_exploration")


func test_defeat_path_still_owned_by_retry_loop() -> void:
	# The retry loop in CutsceneDirector._step_battle calls _start_battle_async
	# on each retry, which frees the stale BattleScene itself. If someone adds
	# an unconditional teardown after the await, that would race the retry.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func start_solo_battle")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 4000)
	# The victory teardown must be conditional (guarded on the result).
	var vi: int = body.find("_return_to_exploration()")
	assert_gt(vi, -1)
	var head := body.substr(maxi(0, vi - 200), 200)
	assert_true("if result" in head,
		"return-to-exploration on the spotlight path must be gated on victory — the defeat retry loop owns its own teardown")
