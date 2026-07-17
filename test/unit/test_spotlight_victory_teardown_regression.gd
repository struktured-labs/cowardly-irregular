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
	# 2026-07-16 bard cap: the teardown must FORCE past the stale-return guard — spotlight resume runs inside the battle_ended emit, before _cleanup_battle sets INACTIVE, so the guard read it as stale and the swayed-alive duel kept ticking behind the aftermath.
	assert_true("if result:" in body and "_return_to_exploration(true)" in body,
		"on victory, start_solo_battle must FORCE return-to-exploration so the stale BattleScene is freed even while BattleManager still reads VICTORY")
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
	var vi: int = body.find("_return_to_exploration(true)")
	assert_gt(vi, -1)
	var head := body.substr(maxi(0, vi - 200), 200)
	assert_true("if result" in head,
		"return-to-exploration on the spotlight path must be gated on victory — the defeat retry loop owns its own teardown")


## ---- 2026-07-16 bard-duel caps: forced teardown + deferred per-job unlock toast ----

func _body_of(src: String, fn: String) -> String:
	var i := src.find("func %s" % fn)
	assert_gt(i, -1, "%s must exist" % fn)
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 4000)


func test_force_flag_threads_through_to_guard() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var start := _body_of(src, "_start_exploration")
	assert_true("not force_battle_teardown and current_state == LoopState.BATTLE" in start,
		"guard must yield to an explicit teardown while still catching stale returns")
	var ret := _body_of(src, "_return_to_exploration")
	assert_true("_start_exploration(force_battle_teardown)" in ret,
		"force flag must thread through _return_to_exploration")


func test_default_call_still_bails_under_decided_battle() -> void:
	# The smoke-fix contract is untouched for every non-forced caller — even
	# in the VICTORY window before _cleanup_battle lands.
	var gl = load("res://src/GameLoop.gd").new()
	autofree(gl)
	gl.current_state = gl.LoopState.BATTLE
	var prior = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.VICTORY
	var child_count_before: int = gl.get_child_count()
	gl._start_exploration()
	assert_eq(gl.current_state, gl.LoopState.BATTLE,
		"unforced return under a decided-but-uncleaned battle must still bail")
	assert_eq(gl.get_child_count(), child_count_before)
	BattleManager.current_state = prior


func test_unlock_toast_deferred_with_per_job_key() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var ended := _body_of(src, "_on_battle_ended")
	assert_true("_pending_spotlight_unlock_toast = _pending_spotlight_unlock" in ended,
		"victory must queue the toast for after the aftermath dialogue")
	var resume := _body_of(src, "_resume_exploration_after_cutscene")
	assert_true("\"spotlight_unlock_\" + _pending_spotlight_unlock_toast" in resume,
		"deferred toast must dedupe PER JOB — the shared key fired once per save, ever")
	assert_true("_pending_spotlight_unlock_toast = \"\"" in resume, "queue must clear after firing")
	var reconcile := _body_of(src, "_reconcile_spotlight_locks")
	assert_true("not _spotlight_duel_active" in reconcile,
		"duels skip the immediate toast — it rendered UNDER the cutscene layer")


func test_tutorial_hints_show_accepts_dedupe_key() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/TutorialHints.gd")
	assert_true("dedupe_key: String = \"\"" in src,
		"show() must accept a dedupe key distinct from the catalog id")
	var body := _body_of(src, "show")
	assert_true("_shown_hints.get(key" in body, "session dedupe must use the key")
	assert_true("\"tutorial_\" + key" in body, "save dedupe must use the key")
	assert_true("hint.show_hint(key" in body,
		"the hint records ITS key on dismiss — recording hint_id would re-shadow all jobs under one flag")
