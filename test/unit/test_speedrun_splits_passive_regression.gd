extends GutTest

## tick 454: speedrun_timer passive's meta_effects.show_splits +
## track_personal_best now actually record splits and PBs per
## boss defeat (and emit a [Splits] battle-log line when the
## passive is equipped).
##
## Pre-fix passives.json authored:
##   speedrun_timer: {meta_effects: {show_splits: true,
##                                    track_personal_best: true}}
##   description: "Persistent timer with split tracking per
##                 dungeon/boss"
## but no code path read either flag. Players equipped Speedrun
## Timer and got nothing — the whole "split tracking" promise was
## decoration.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const GAME_STATE_PATH := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_fields_persisted() -> void:
	var src := _read(GAME_STATE_PATH)
	assert_true(src.contains("var boss_splits: Dictionary = {}"),
		"GameState must declare boss_splits Dictionary field")
	assert_true(src.contains("var boss_personal_best: Dictionary = {}"),
		"GameState must declare boss_personal_best Dictionary field")
	assert_true(src.contains("\"boss_splits\": boss_splits.duplicate(true)"),
		"to_dict must persist boss_splits (deep-copied)")
	assert_true(src.contains("\"boss_personal_best\": boss_personal_best.duplicate(true)"),
		"to_dict must persist boss_personal_best (deep-copied)")


func test_load_uses_variant_guard() -> void:
	# Variant-typed dict guard so a malformed save can't overwrite
	# the field with non-dict garbage.
	var src := _read(GAME_STATE_PATH)
	assert_true(src.contains("save_data[\"boss_splits\"] is Dictionary"),
		"load must guard boss_splits with `is Dictionary` before assigning")
	assert_true(src.contains("save_data[\"boss_personal_best\"] is Dictionary"),
		"load must guard boss_personal_best with `is Dictionary` before assigning")


func test_record_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _record_boss_split"),
		"BattleManager must declare _record_boss_split helper")
	assert_true(src.contains("GameState.boss_splits[boss_id] = now"),
		"helper must store the first-clear split")
	assert_true(src.contains("GameState.boss_personal_best[boss_id] = now"),
		"helper must update the personal best when current run is faster")


func test_emit_gate_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _party_wants_splits_emit"),
		"BattleManager must declare _party_wants_splits_emit helper")
	assert_true(src.contains("me.get(\"show_splits\", false)"),
		"emit gate must read show_splits from passive meta_effects")


func test_pb_marker_in_emit() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("★ NEW PB"),
		"new PBs must get a gold ★ marker so the player feels the win")


func test_victory_calls_record() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# end_battle's boss loop must call _record_boss_split after
	# adding to previously_fought_bosses.
	var idx: int = src.find("_record_boss_split(boss_id, enemy.combatant_name)")
	assert_gt(idx, -1,
		"end_battle must invoke _record_boss_split on each defeated boss")


func test_data_still_authors_flags() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("speedrun_timer"))
	var me: Variant = data["speedrun_timer"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("show_splits", false)))
	assert_true(bool(me.get("track_personal_best", false)))


func test_runtime_record_stores_first_clear() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	# Stash prior state.
	var prior_splits: Dictionary = gs.boss_splits.duplicate(true)
	var prior_pbs: Dictionary = gs.boss_personal_best.duplicate(true)
	var prior_pt: float = float(gs.playtime_seconds)
	gs.boss_splits = {}
	gs.boss_personal_best = {}
	gs.playtime_seconds = 600.0
	bm._record_boss_split("test_first_clear_boss", "Test Boss")
	assert_eq(float(gs.boss_splits.get("test_first_clear_boss", -1.0)), 600.0,
		"first defeat must stamp playtime_seconds into boss_splits")
	assert_eq(float(gs.boss_personal_best.get("test_first_clear_boss", -1.0)), 600.0,
		"first defeat must also be the initial personal best")
	# Restore.
	gs.boss_splits = prior_splits
	gs.boss_personal_best = prior_pbs
	gs.playtime_seconds = prior_pt


func test_runtime_pb_only_improves() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	var prior_splits: Dictionary = gs.boss_splits.duplicate(true)
	var prior_pbs: Dictionary = gs.boss_personal_best.duplicate(true)
	var prior_pt: float = float(gs.playtime_seconds)
	gs.boss_splits = {"pb_boss": 500.0}
	gs.boss_personal_best = {"pb_boss": 500.0}
	# Slower run — PB must NOT degrade.
	gs.playtime_seconds = 700.0
	bm._record_boss_split("pb_boss", "PB Boss")
	assert_eq(float(gs.boss_personal_best["pb_boss"]), 500.0,
		"a slower run must NOT degrade the personal best")
	# Faster run — PB updates, splits stay at first-clear.
	gs.playtime_seconds = 400.0
	bm._record_boss_split("pb_boss", "PB Boss")
	assert_eq(float(gs.boss_personal_best["pb_boss"]), 400.0,
		"a faster run must improve the personal best")
	assert_eq(float(gs.boss_splits["pb_boss"]), 500.0,
		"first-clear split stamp must NOT change on later runs")
	gs.boss_splits = prior_splits
	gs.boss_personal_best = prior_pbs
	gs.playtime_seconds = prior_pt
