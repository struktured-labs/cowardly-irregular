extends GutTest

## tick 448: speedrun_mode passive's meta_effects.movement_speed_
## bonus now actually scales OverworldPlayer's base_speed.
##
## Pre-fix passives.json authored:
##   speedrun_mode: {meta_effects: {show_timer: true,
##                                   movement_speed_bonus: 1.5}}
##   description: "Show speedrun timer, +50% movement speed on
##                 overworld"
## but no code path read the bonus. Equipping speedrun_mode left
## velocity unchanged — only the show_timer half of the promise
## was (potentially) doing anything.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("func _party_movement_speed_bonus"),
		"OverworldPlayer must declare _party_movement_speed_bonus helper")
	assert_true(src.contains("me.get(\"movement_speed_bonus\", 1.0)"),
		"helper must read movement_speed_bonus from passive meta_effects")


func test_movement_path_consults_helper() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("_party_movement_speed_bonus()"),
		"OverworldPlayer movement path must consult _party_movement_speed_bonus")
	assert_true(src.contains("base_speed *= move_bonus"),
		"the bonus must MULTIPLY base_speed (not replace it)")


func test_helper_max_wins() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _party_movement_speed_bonus")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if b > best:"),
		"helper must use max-wins semantics across party passives")


func test_helper_defaults_to_1_0() -> void:
	# Default 1.0 means "no bonus" — a missing GameState or
	# PassiveSystem must NOT slow the player to 0.
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _party_movement_speed_bonus")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Both fallback returns must be 1.0, and best starts at 1.0.
	var ret_1: int = body.count("return 1.0")
	assert_gt(ret_1, 1,
		"helper must return 1.0 on missing autoloads (no fallback slow-down)")
	assert_true(body.contains("var best: float = 1.0"),
		"best must initialize to 1.0 so a passive-less party gets unmodified speed")


func test_data_still_authors_bonus() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("speedrun_mode"))
	var me: Variant = data["speedrun_mode"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("movement_speed_bonus", 0.0)), 1.0,
		"speedrun_mode must still author movement_speed_bonus > 1.0")


func test_runtime_no_passive_returns_1_0() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "Plodder", "equipped_passives": []})
	gs.player_party = typed
	assert_eq(p._party_movement_speed_bonus(), 1.0,
		"party without speedrun_mode must return 1.0 (no silent bonus)")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_with_passive_returns_bonus() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("speedrun_mode"):
		pending("speedrun_mode passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "Runner", "equipped_passives": ["speedrun_mode"]})
	gs.player_party = typed
	assert_almost_eq(p._party_movement_speed_bonus(), 1.5, 0.001,
		"speedrun_mode-equipped party must return the authored 1.5 bonus")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_max_wins_no_compound() -> void:
	# Three speedrun_mode equips must still cap at 1.5, not 1.5^3.
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("speedrun_mode"):
		pending("speedrun_mode passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "A", "equipped_passives": ["speedrun_mode"]})
	typed.append({"name": "B", "equipped_passives": ["speedrun_mode"]})
	typed.append({"name": "C", "equipped_passives": ["speedrun_mode"]})
	gs.player_party = typed
	assert_almost_eq(p._party_movement_speed_bonus(), 1.5, 0.001,
		"three speedrun_mode equips must NOT compound — max-wins caps at 1.5")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore
