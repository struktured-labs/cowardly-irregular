extends GutTest

## tick 455: content_radar passive's meta_effects.show_treasure
## now actually counts and displays nearby unopened treasure
## chests via the speedrun HUD's content_radar label.
##
## Pre-fix passives.json authored:
##   content_radar: {meta_effects: {show_secrets: true,
##                                   show_treasure: true}}
##   description: "Show nearby treasure, secrets, and optional
##                 content on the map"
## but no code path read either flag. Players equipped Content
## Radar and got no help finding chests — the whole passive was
## decoration.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"
const CHEST_PATH := "res://src/exploration/TreasureChest.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_chest_registers_in_group() -> void:
	var src := _read(CHEST_PATH)
	assert_true(src.contains("add_to_group(\"treasure\")"),
		"TreasureChest._ready must add the chest to the \"treasure\" group")


func test_gate_helper_exists() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("func _party_wants_show_treasure"),
		"OverworldPlayer must declare _party_wants_show_treasure helper")
	assert_true(src.contains("me.get(\"show_treasure\", false)"),
		"helper must read show_treasure from passive meta_effects")


func test_radar_builder_exists() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("func _build_radar_text"),
		"OverworldPlayer must declare _build_radar_text helper")
	assert_true(src.contains("get_nodes_in_group(\"treasure\")"),
		"radar builder must scan the \"treasure\" group")
	# Pin the opened/unopened filter.
	assert_true(src.contains("_is_opened\" in c"),
		"radar builder must filter on `_is_opened in c` so opened chests don't count")


func test_hud_includes_radar_label() -> void:
	var src := _read(PLAYER_PATH)
	# Label initialization in _init_speedrun_hud.
	assert_true(src.contains("var _content_radar_label: Label = null"),
		"OverworldPlayer must declare _content_radar_label field")
	assert_true(src.contains("_content_radar_label = Label.new()"),
		"_init_speedrun_hud must build the content_radar label")
	# Tick consumer must update it independently of the timer gate.
	var idx: int = src.find("_party_wants_show_treasure()")
	assert_gt(idx, -1, "_on_speedrun_hud_tick must consult the radar gate")
	var window: String = src.substr(idx, 200)
	assert_true(window.contains("_content_radar_label.visible") or window.contains("_content_radar_label.text"),
		"_on_speedrun_hud_tick must update the radar label visibility/text")


func test_data_still_authors_flag() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("content_radar"))
	var me: Variant = data["content_radar"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("show_treasure", false)),
		"content_radar must still author show_treasure = true")


func test_runtime_no_passive_gate_false() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "Plain", "equipped_passives": []})
	gs.player_party = typed
	assert_false(p._party_wants_show_treasure(),
		"vanilla party must not request treasure radar")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_with_passive_gate_true() -> void:
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("content_radar"):
		pending("content_radar passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var typed: Array[Dictionary] = []
	typed.append({"name": "Treasurer", "equipped_passives": ["content_radar"]})
	gs.player_party = typed
	assert_true(p._party_wants_show_treasure(),
		"content_radar-equipped party must request treasure radar")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_radar_text_empty_when_no_chests() -> void:
	# Sanity: empty group returns "" (no point showing 0).
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	# No chests in scene tree → no group members.
	assert_eq(p._build_radar_text(), "",
		"no chests in group → empty string (don't show 0 treasure)")
