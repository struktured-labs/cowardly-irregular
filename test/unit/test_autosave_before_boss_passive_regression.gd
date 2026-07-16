extends GutTest

## tick 447: autosave passive's meta_effects.auto_save_before_boss
## now actually fires a quicksave before the boss intro plays.
##
## Pre-fix passives.json authored:
##   autosave: {meta_effects: {auto_save_before_boss: true,
##                              auto_save_interval: 300}}
##   description: "Automatically save before boss fights and
##                 dangerous encounters"
## but no code path read the field. A wipe rewound to the last
## village save, costing dungeon progress — the very thing the
## passive was supposed to protect.

const DRAGON_CAVE_PATH := "res://src/maps/dungeons/DragonCave.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(DRAGON_CAVE_PATH)
	assert_true(src.contains("func _party_wants_auto_save_before_boss"),
		"DragonCave must declare _party_wants_auto_save_before_boss helper")
	assert_true(src.contains("me.get(\"auto_save_before_boss\", false)"),
		"helper must read auto_save_before_boss from passive meta_effects")


func test_trigger_boss_battle_consults_helper() -> void:
	var src := _read(DRAGON_CAVE_PATH)
	var fn_idx: int = src.find("func _trigger_boss_battle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_wants_auto_save_before_boss()"),
		"_trigger_boss_battle must consult _party_wants_auto_save_before_boss")
	assert_true(body.contains("force_quick_save()"),
		"_trigger_boss_battle must call SaveSystem.force_quick_save when the passive is equipped")


func test_save_fires_before_battle_emit() -> void:
	# Pin ordering: the autosave block sits ABOVE the
	# battle_triggered.emit call, so the save captures the
	# pre-boss state, not the post-defeat one.
	var src := _read(DRAGON_CAVE_PATH)
	var fn_idx: int = src.find("func _trigger_boss_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var save_idx: int = body.find("force_quick_save")
	var emit_idx: int = body.find("battle_triggered.emit")
	assert_gt(save_idx, -1)
	assert_gt(emit_idx, -1)
	assert_lt(save_idx, emit_idx,
		"the force_quick_save must precede battle_triggered.emit (save captures pre-boss state)")


func test_any_wins_semantics() -> void:
	# Pin that the helper returns at first hit — any one party
	# member equipping autosave triggers the save.
	var src := _read(DRAGON_CAVE_PATH)
	var fn_idx: int = src.find("func _party_wants_auto_save_before_boss")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# An early `return true` indicates any-wins.
	assert_true(body.contains("return true") and body.contains("return false"),
		"helper must early-return true on first hit (any-wins) and false on no-hit")


func test_data_still_authors_field() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("autosave"))
	var me: Variant = data["autosave"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("auto_save_before_boss", false)),
		"autosave passive must still author auto_save_before_boss = true")


func test_runtime_helper_false_for_empty_party() -> void:
	var dc_script: GDScript = load(DRAGON_CAVE_PATH)
	var dc: Node = dc_script.new()
	# Minimal layout so _ready's map-gen doesn't warn "No layout for floor 1" — base DragonCave has none (subclasses author them); this test exercises the autosave passive, not map gen.
	dc.floor_layouts = {1: ["P"]}
	add_child_autofree(dc)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var empty: Array[Dictionary] = []
	gs.player_party = empty
	assert_false(dc._party_wants_auto_save_before_boss(),
		"empty party must return false — fix must not silently trigger save")
	var restore_party: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore_party.append(m)
	gs.player_party = restore_party


func test_runtime_helper_true_when_equipped() -> void:
	var dc_script: GDScript = load(DRAGON_CAVE_PATH)
	var dc: Node = dc_script.new()
	# Minimal layout so _ready's map-gen doesn't warn "No layout for floor 1" — base DragonCave has none (subclasses author them); this test exercises the autosave passive, not map gen.
	dc.floor_layouts = {1: ["P"]}
	add_child_autofree(dc)
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("autosave"):
		pending("autosave passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var party: Array[Dictionary] = []
	party.append({"name": "Saver", "equipped_passives": ["autosave"]})
	gs.player_party = party
	assert_true(dc._party_wants_auto_save_before_boss(),
		"party with autosave equipped must trigger the save hook")
	var restore_party: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore_party.append(m)
	gs.player_party = restore_party
