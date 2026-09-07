extends GutTest

## show_secrets HUD wire (2026-07-01). content_radar's meta_effects
## authors BOTH show_treasure and show_secrets; tick 455 wired only
## treasure because no secret ENTITIES existed to count. cowir-
## overworld's HiddenPassage (3a5ac00f, PR #14) made secrets first-
## class, mirroring the treasure-group contract exactly — this wire
## completes the passive's promise: "◈ N secrets" segment on the
## radar label counting undiscovered passages.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_secrets_gate_helper_exists() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("func _party_wants_show_secrets"),
		"OverworldPlayer must declare _party_wants_show_secrets helper")
	assert_true(src.contains("me.get(\"show_secrets\", false)"),
		"helper must read show_secrets from passive meta_effects")


func test_radar_builder_counts_secrets_group() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _build_radar_text")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_nodes_in_group(\"secrets\")"),
		"radar builder must scan the \"secrets\" group (HiddenPassage contract)")
	assert_true(body.contains("_is_discovered\" in s"),
		"radar builder must filter on `_is_discovered in s` so found passages don't count")


func test_segments_gated_independently() -> void:
	# Each segment must sit behind ITS OWN passive flag — a future
	# passive authoring only show_secrets must not light the treasure
	# count and vice versa.
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _build_radar_text")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if _party_wants_show_treasure():"),
		"treasure segment must be gated on _party_wants_show_treasure inside the builder")
	assert_true(body.contains("if _party_wants_show_secrets():"),
		"secrets segment must be gated on _party_wants_show_secrets inside the builder")


func test_tick_lights_label_on_either_flag() -> void:
	var src := _read(PLAYER_PATH)
	assert_true(src.contains("_party_wants_show_treasure() or _party_wants_show_secrets()"),
		"HUD tick must light the radar label when EITHER radar flag is on")


func test_data_still_authors_show_secrets() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("content_radar"))
	var me: Variant = (data["content_radar"] as Dictionary).get("meta_effects", {})
	assert_true(bool((me as Dictionary).get("show_secrets", false)),
		"content_radar must still author show_secrets = true")


func test_runtime_empty_groups_empty_text() -> void:
	# Bare player, no chests/secrets in tree → "" regardless of gates.
	var script: GDScript = load(PLAYER_PATH)
	var p: Node = script.new()
	add_child_autofree(p)
	assert_eq(p._build_radar_text(), "",
		"no treasure + no secrets in groups → empty radar text")


func test_runtime_secrets_gate_matches_passive() -> void:
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
	var no_radar: Array[Dictionary] = []
	no_radar.append({"name": "Plain", "equipped_passives": []})
	gs.player_party = no_radar
	assert_false(p._party_wants_show_secrets(),
		"party without content_radar must not request secrets")
	var with_radar: Array[Dictionary] = []
	with_radar.append({"name": "Seeker", "equipped_passives": ["content_radar"]})
	gs.player_party = with_radar
	assert_true(p._party_wants_show_secrets(),
		"content_radar-equipped party must request secrets")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore
