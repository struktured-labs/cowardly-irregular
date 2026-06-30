extends GutTest

## tick 446: save_protection passive's meta_effects.corruption_
## resistance now actually reduces save corruption gain from meta
## abilities (and any other add_corruption call site).
##
## Pre-fix passives.json authored:
##   save_protection: {meta_effects: {corruption_resistance: 0.5}}
##   description: "Reduces save corruption from meta abilities by 50%"
## but no code path read the field. Necromancer / Bossbinder / etc.
## abilities racked up corruption at the full authored rate even
## with save_protection equipped on the whole party.

const GAME_STATE_PATH := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(GAME_STATE_PATH)
	assert_true(src.contains("func _party_corruption_resistance"),
		"GameState must declare _party_corruption_resistance helper")
	assert_true(src.contains("me.get(\"corruption_resistance\", 0.0)"),
		"helper must read corruption_resistance from passive meta_effects")


func test_add_corruption_consults_helper() -> void:
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func add_corruption")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_corruption_resistance()"),
		"add_corruption must consult _party_corruption_resistance")
	assert_true(body.contains("amount * (1.0 - clampf(resist, 0.0, 1.0))"),
		"add_corruption must scale by (1 - resist) — a fractional resist still applies, full resist (1.0) cancels")


func test_helper_max_wins() -> void:
	# Pin max-wins semantics so duplicate equips don't stack to
	# immunity by accident.
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func _party_corruption_resistance")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if r > best:"),
		"helper must use max-wins semantics across party passives")


func test_negative_amount_passes_through() -> void:
	# Pin that the resistance does NOT shrink negative deltas
	# (corruption clearing flows through unmodified).
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func add_corruption")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount > 0.0:"),
		"add_corruption must gate the resist on amount > 0.0 (negative deltas pass through)")


func test_data_still_authors_resistance() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("save_protection"))
	var me: Variant = data["save_protection"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("corruption_resistance", 0.0)), 0.0,
		"save_protection must still author corruption_resistance > 0")


func test_runtime_no_passive_full_corruption() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	# Snapshot, clean party, baseline corruption.
	var prior_party: Array = gs.player_party.duplicate(true)
	var prior_corruption: float = gs.corruption_level
	var typed_party: Array[Dictionary] = []
	typed_party.append({"name": "Nobody", "equipped_passives": []})
	gs.player_party = typed_party
	gs.corruption_level = 0.0
	gs.add_corruption(0.2)
	assert_almost_eq(gs.corruption_level, 0.2, 0.001,
		"vanilla party (no save_protection) must take full corruption — fix must not silently reduce baseline")
	# Restore.
	var restore_party: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore_party.append(m)
	gs.player_party = restore_party
	gs.corruption_level = prior_corruption


func test_runtime_with_passive_halved_corruption() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("save_protection"):
		pending("save_protection passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var prior_corruption: float = gs.corruption_level
	var typed_party: Array[Dictionary] = []
	typed_party.append({"name": "Protected", "equipped_passives": ["save_protection"]})
	gs.player_party = typed_party
	gs.corruption_level = 0.0
	gs.add_corruption(0.2)
	# 0.5 resistance → 0.2 * (1 - 0.5) = 0.1.
	assert_almost_eq(gs.corruption_level, 0.1, 0.001,
		"save_protection-equipped party must take half corruption")
	var restore_party: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore_party.append(m)
	gs.player_party = restore_party
	gs.corruption_level = prior_corruption


func test_runtime_max_wins_no_stack() -> void:
	# Two party members with save_protection equipped must NOT
	# stack to immunity — max-wins.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "GameState autoload must be present")
	if gs == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("save_protection"):
		pending("save_protection passive required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var prior_corruption: float = gs.corruption_level
	var typed_party: Array[Dictionary] = []
	typed_party.append({"name": "A", "equipped_passives": ["save_protection"]})
	typed_party.append({"name": "B", "equipped_passives": ["save_protection"]})
	typed_party.append({"name": "C", "equipped_passives": ["save_protection"]})
	gs.player_party = typed_party
	gs.corruption_level = 0.0
	gs.add_corruption(0.2)
	# Three equips of 0.5 resist still gives 0.5 (max-wins) → 0.1 gain.
	assert_almost_eq(gs.corruption_level, 0.1, 0.001,
		"three save_protection equips must NOT stack — max-wins still applies 0.5 resist")
	var restore_party: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore_party.append(m)
	gs.player_party = restore_party
	gs.corruption_level = prior_corruption
