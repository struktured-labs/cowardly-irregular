extends GutTest

## tick 449: autosave passive's meta_effects.auto_save_interval now
## actually fires a periodic quicksave during overworld traversal.
##
## Pre-fix passives.json authored:
##   autosave: {meta_effects: {auto_save_before_boss: true,
##                              auto_save_interval: 300}}
##   description: "Automatically save before boss fights and
##                 dangerous encounters"
## but no code path read auto_save_interval. The "dangerous
## encounters" half of the description — periodic-during-overworld
## protection — was decoration.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_interval_helper_exists() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("func _party_auto_save_interval"),
		"OverworldPlayer must declare _party_auto_save_interval helper")
	assert_true(src.contains("me.get(\"auto_save_interval\", 0.0)"),
		"helper must read auto_save_interval from passive meta_effects")


func test_ready_sets_up_timer() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _ready")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_init_autosave_timer"),
		"_ready must call _init_autosave_timer")


func test_init_timer_uses_party_helper() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _init_autosave_timer")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_auto_save_interval()"),
		"_init_autosave_timer must consult _party_auto_save_interval for the wait_time")
	assert_true(body.contains("timeout.connect(_on_autosave_timer_timeout)"),
		"_init_autosave_timer must connect timeout to _on_autosave_timer_timeout")


func test_timeout_skips_during_battle() -> void:
	# Pin the battle-state guard so a periodic autosave doesn't
	# overwrite the per-boss save fired by tick 447's pre-boss hook.
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _on_autosave_timer_timeout")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("current_state") and body.contains("if st != 0"),
		"_on_autosave_timer_timeout must skip when BattleManager.current_state != INACTIVE")
	assert_true(body.contains("force_quick_save"),
		"_on_autosave_timer_timeout must call SaveSystem.force_quick_save on the safe path")


func test_helper_smallest_interval_wins() -> void:
	# Pin smallest-wins semantics so a Speedrunner-style passive
	# authoring a shorter interval overrides the default 300.
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _party_auto_save_interval")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if v > 0.0 and (best == 0.0 or v < best):"),
		"helper must keep the smallest non-zero interval (most-frequent saves win)")


func test_data_still_authors_interval() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("autosave"))
	var me: Variant = data["autosave"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("auto_save_interval", 0.0)), 0.0,
		"autosave passive must still author auto_save_interval > 0")


func test_runtime_no_passive_zero_interval() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "NoPass", "equipped_passives": []})
	gs.player_party = typed
	assert_eq(p._party_auto_save_interval(), 0.0,
		"party without autosave must return 0.0 (timer stays idle)")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_with_passive_returns_authored() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("autosave"):
		pending("autosave passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "Saver", "equipped_passives": ["autosave"]})
	gs.player_party = typed
	var iv: float = p._party_auto_save_interval()
	assert_gt(iv, 0.0,
		"autosave-equipped party must return the authored interval")
	# Loose check: should be the authored 300 (or another author-edited value).
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var me: Variant = data["autosave"].get("meta_effects", {})
	assert_almost_eq(iv, float(me.get("auto_save_interval", 0.0)), 0.001,
		"runtime interval must match the authored value")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore
