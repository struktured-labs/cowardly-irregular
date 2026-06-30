extends GutTest

## tick 464: OverworldPlayer's tick 449/450/455 HUD + Timer setup is
## deferred to the next idle frame.
##
## User report (post-v3.30.0-alpha):
##   "after the first RE it goes to a black screen and freezes"
## on the web build (itch.io). The 9d5a496d await fix is in place,
## but recent ticks (449/450/455) load OverworldPlayer's _ready with
## Timer + CanvasLayer + Label allocations that can delay first-
## frame paint on slow browsers. Deferring these to the next
## process_frame keeps the scene visible immediately while the
## passive-driven hooks finish wiring on the following idle tick.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_ready_defers_passive_hook_setup() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _ready")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("call_deferred(\"_init_passive_hooks\")"),
		"_ready must defer passive hook setup via call_deferred(\"_init_passive_hooks\") so first-frame paint isn't blocked")
	# Pin that _ready does NOT directly call the heavy setups anymore
	# (so any later refactor doesn't silently re-introduce the blocking).
	# The direct calls should now live behind _init_passive_hooks.
	assert_false(body.contains("\n\t_init_autosave_timer()"),
		"_ready must NOT directly call _init_autosave_timer — defer it via _init_passive_hooks")
	assert_false(body.contains("\n\t_init_speedrun_hud()"),
		"_ready must NOT directly call _init_speedrun_hud — defer it via _init_passive_hooks")


func test_init_passive_hooks_guards_tree_membership() -> void:
	# A scene torn down between _ready and the deferred call must not
	# error. The guard short-circuits on not is_inside_tree().
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _init_passive_hooks")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if not is_inside_tree():"),
		"_init_passive_hooks must guard on is_inside_tree() — scene tear-down between _ready and idle must be safe")
	# Both heavy setups must still be invoked.
	assert_true(body.contains("_init_autosave_timer()"),
		"_init_passive_hooks must invoke _init_autosave_timer")
	assert_true(body.contains("_init_speedrun_hud()"),
		"_init_passive_hooks must invoke _init_speedrun_hud")


func test_runtime_deferred_setup_eventually_runs() -> void:
	# Construct an OverworldPlayer, add to tree, wait one frame, and
	# verify the deferred init actually fired (autosave_timer + HUD
	# layer both present).
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	# At end of _ready the deferred call is queued, not run.
	# Wait one idle frame for call_deferred to process.
	await get_tree().process_frame
	await get_tree().process_frame
	var has_timer: bool = false
	var has_hud: bool = false
	for child in p.get_children():
		if child is Timer and child.name == "AutosaveTimer":
			has_timer = true
		if child is CanvasLayer and child.name == "SpeedrunHUD":
			has_hud = true
	assert_true(has_timer,
		"AutosaveTimer must exist after the deferred _init_passive_hooks runs")
	assert_true(has_hud,
		"SpeedrunHUD CanvasLayer must exist after the deferred _init_passive_hooks runs")
