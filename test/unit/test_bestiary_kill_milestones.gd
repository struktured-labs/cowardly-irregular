extends GutTest

## tick 264: kill-milestone signal (10/50/100/500 per monster).
##
## When mark_defeated crosses one of the milestone thresholds EXACTLY,
## GameState.bestiary_kill_milestone fires with monster_id + display
## name + count. GameLoop turns this into a Toast — visible reward
## feedback for the grind loop.
##
## Strict equality is the contract: 11/12/13 don't re-fire because
## "milestone announced" should be a one-shot per pair across the
## save. 9 → 10 fires; 10 → 11 doesn't; 11 → 12 doesn't; …; 49 → 50
## fires; etc.


func before_each() -> void:
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants.erase("defeated_counts")
	BestiarySystem.reload()


# ── Milestone list pinned ─────────────────────────────────────────

func test_milestone_list_is_10_50_100_500() -> void:
	# Pin the list so it can't drift to something arbitrary without
	# updating the test (and the player-facing copy).
	assert_eq(BestiarySystem.KILL_MILESTONES, [10, 50, 100, 500],
		"milestone list must be exactly [10, 50, 100, 500] (UI copy + suite assume this)")


# ── Signal fires on exact crossing ────────────────────────────────

func test_signal_fires_on_first_milestone() -> void:
	watch_signals(GameState)
	# 9 kills — nothing yet.
	for i in range(9):
		BestiarySystem.mark_defeated("slime")
	assert_signal_not_emitted(GameState, "bestiary_kill_milestone",
		"signal must not fire before the threshold")
	# 10th kill.
	BestiarySystem.mark_defeated("slime")
	assert_signal_emitted(GameState, "bestiary_kill_milestone",
		"signal must fire on the 10th kill")


func test_signal_fires_with_correct_parameters() -> void:
	if BestiarySystem.get_monster_data("slime").is_empty():
		push_warning("[test] slime missing from monsters.json — skipping")
		return
	watch_signals(GameState)
	for i in range(10):
		BestiarySystem.mark_defeated("slime")
	var data: Dictionary = BestiarySystem.get_monster_data("slime")
	var expected_name: String = str(data.get("name", "Slime"))
	assert_signal_emitted_with_parameters(GameState, "bestiary_kill_milestone",
		["slime", expected_name, 10],
		"signal must emit (monster_id, display_name, milestone_count)")


# ── Strict-equality: no re-fire between milestones ────────────────

func test_signal_does_not_re_fire_between_milestones() -> void:
	# Kill 11 — only milestone 10 should fire (1 emission, not 2).
	watch_signals(GameState)
	for i in range(11):
		BestiarySystem.mark_defeated("slime")
	assert_signal_emit_count(GameState, "bestiary_kill_milestone", 1,
		"only ONE signal emission expected (the 10th kill) — 11th must NOT re-fire")


func test_signal_fires_on_each_milestone_progression() -> void:
	# Kill 100 — should fire 3 times: at 10, 50, and 100.
	watch_signals(GameState)
	for i in range(100):
		BestiarySystem.mark_defeated("slime")
	assert_signal_emit_count(GameState, "bestiary_kill_milestone", 3,
		"3 emissions expected across 100 kills: 10, 50, 100")


# ── Per-monster scoping: kills cross between monsters don't fire ─

func test_signal_scoped_per_monster() -> void:
	# 9 slime + 9 bat = no milestone crossings.
	watch_signals(GameState)
	for i in range(9):
		BestiarySystem.mark_defeated("slime")
		BestiarySystem.mark_defeated("bat")
	assert_signal_not_emitted(GameState, "bestiary_kill_milestone",
		"9 slime + 9 bat must not fire any milestone — counters are per-monster")


# ── GameLoop wires the handler ────────────────────────────────────

func test_game_loop_wires_handler_to_toast() -> void:
	# Source pin: GameLoop._ready must connect to the signal, and the
	# handler must call Toast.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("GameState.bestiary_kill_milestone.connect(_on_bestiary_kill_milestone)"),
		"GameLoop._ready must connect bestiary_kill_milestone to its handler")
	assert_true(src.contains("func _on_bestiary_kill_milestone"),
		"handler must exist")
	# Find the handler body and check for Toast call.
	var idx: int = src.find("func _on_bestiary_kill_milestone")
	var next_func: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next_func - idx) if next_func > 0 else 600)
	assert_true(body.contains("Toast.show_success"),
		"handler must call Toast.show_success (matches event_chat_unlocked pattern)")


# ── Reset between battles: don't re-fire on save → load → re-kill ─

func test_milestone_does_not_re_fire_on_subsequent_kills_past_threshold() -> void:
	# Pin the strict-equality semantics for a save/load scenario:
	# kill 10 (fires), kill 11 (doesn't), kill 12 (doesn't). After
	# save+load the count would be 12 — no re-fire on continued
	# grinding past the threshold.
	watch_signals(GameState)
	for i in range(12):
		BestiarySystem.mark_defeated("slime")
	assert_signal_emit_count(GameState, "bestiary_kill_milestone", 1,
		"only the 10th-kill crossing fires; 11th and 12th are above the threshold and don't re-emit")
