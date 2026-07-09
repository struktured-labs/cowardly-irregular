extends GutTest

## Regression (2026-07-08, cowir-sfx finding): F1 activated 26 enemy status
## effects but BattleScene's status-audio match only dispatched 4 of them —
## doom/curse/silence/stun/burn/freeze/... landed with ZERO audio. The match
## now ends in a play_status(effect) catch-all (manifest lookup + generic
## fallback) so no future effect can land silently, and the scary statuses
## got bespoke assets. This pins the catch-all, the empty-effect guard, and
## the bespoke manifest keys.

const BS_PATH := "res://src/battle/BattleScene.gd"


func test_bespoke_status_assets_registered() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = manifest.get("sfx", {})
	for key in ["status_doom", "status_curse", "status_silence"]:
		assert_true(sfx.has(key), "%s must be in sfx_manifest (cowir-sfx status branch)" % key)
		var path := "res://assets/audio/sfx/%s.ogg" % key
		assert_true(ResourceLoader.exists(path), "%s asset must exist on disk" % path)


func test_dispatch_has_catch_all_after_empty_guard() -> void:
	var src := FileAccess.get_file_as_string(BS_PATH)
	var block_start := src.find("func _on_action_executed")
	assert_gt(block_start, 0, "dispatch host must exist")
	var block := src.substr(block_start, 2200)
	var empty_guard := block.find("\"\":")
	var catch_all := block.find("_:")
	assert_gt(empty_guard, 0, "match must guard the empty effect BEFORE the catch-all (most abilities have no effect)")
	assert_gt(catch_all, empty_guard, "match must end in a play_status(effect) catch-all so no status lands silently")
	assert_true("SoundManager.play_status(effect)" in block,
		"catch-all must route through play_status (manifest lookup + generic fallback)")


func test_every_live_ability_effect_routes_to_audio() -> void:
	# Every effect that can actually fire (effect_chance > 0 or random_debuff)
	# must hit a non-empty match arm. With the catch-all this is true by
	# construction — this asserts the DATA side stays inside the match's
	# reachable space (an empty-string effect with a chance would be silent).
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	for aid in abilities:
		var ab = abilities[aid]
		if typeof(ab) != TYPE_DICTIONARY:
			continue
		var eff := str(ab.get("effect", ""))
		var live: bool = float(ab.get("effect_chance", 0.0)) > 0.0 or eff == "random_debuff"
		if live:
			assert_ne(eff, "", "ability '%s' has an effect_chance but an empty effect — audio (and the effect itself) would silently no-op" % aid)
