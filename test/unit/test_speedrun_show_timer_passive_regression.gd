extends GutTest

## tick 450: speedrun_mode passive's meta_effects.show_timer now
## actually displays a small overworld playtime HUD.
##
## Pre-fix passives.json authored:
##   speedrun_mode: {meta_effects: {show_timer: true,
##                                   movement_speed_bonus: 1.5}}
##   description: "Show speedrun timer, +50% movement speed on
##                 overworld"
## The movement_speed_bonus half was wired in tick 448 but
## show_timer was pure decoration — equipping speedrun_mode
## gave a faster sprite with no HUD.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("func _party_wants_show_timer"),
		"OverworldPlayer must declare _party_wants_show_timer helper")
	assert_true(src.contains("me.get(\"show_timer\", false)"),
		"helper must read show_timer from passive meta_effects")


func test_ready_inits_hud() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _ready")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_init_speedrun_hud"),
		"_ready must call _init_speedrun_hud")


func test_init_builds_canvas_layer() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _init_speedrun_hud")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("CanvasLayer.new()"),
		"HUD must live on a CanvasLayer so it floats above the world")
	assert_true(body.contains("Label.new()"),
		"HUD must use a Label for the timer text")
	# 90 keeps the HUD above gameplay but below high-priority menus.
	assert_true(body.contains("_speedrun_hud_layer.layer = 90"),
		"HUD layer must be 90 (above gameplay, doesn't collide with menu layers)")
	assert_true(body.contains("timeout.connect(_on_speedrun_hud_tick)"),
		"the 1Hz timer must drive _on_speedrun_hud_tick")


func test_tick_consults_gate_and_playtime() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _on_speedrun_hud_tick")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_wants_show_timer()"),
		"_on_speedrun_hud_tick must consult the visibility gate each second")
	assert_true(body.contains("get_playtime_formatted"),
		"_on_speedrun_hud_tick must read GameState.get_playtime_formatted")
	assert_true(body.contains("visible = visible_now"),
		"the label's visible flag must mirror the gate (passive un/equip flows live)")


func test_data_still_authors_show_timer() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("speedrun_mode"))
	var me: Variant = data["speedrun_mode"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("show_timer", false)),
		"speedrun_mode must still author show_timer = true")


func test_runtime_no_passive_returns_false() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "NoTimer", "equipped_passives": []})
	gs.player_party = typed
	assert_false(p._party_wants_show_timer(),
		"vanilla party must not request HUD — fix must not silently enable for everyone")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_with_passive_returns_true() -> void:
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
	typed.append({"name": "Speedy", "equipped_passives": ["speedrun_mode"]})
	gs.player_party = typed
	assert_true(p._party_wants_show_timer(),
		"speedrun_mode-equipped party must request HUD visibility")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore
